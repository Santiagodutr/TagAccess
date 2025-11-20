# TagPass - RFID Access Management System

## Overview

TagPass is a comprehensive access control system that combines cloud-based administration with edge computing for real-time RFID card reader management. The system enables institutions to control physical access to spaces through RFID cards, with centralized administration through a web dashboard and distributed offline capabilities through Raspberry Pi devices.

The architecture follows a hybrid cloud-local model: Supabase PostgreSQL serves as the authoritative data source and administrative interface, while Raspberry Pi devices maintain local SQLite caches for zero-latency access decisions and continued operation during network outages.

## Key Features

- **Real-Time Access Control**: RFID card readers provide sub-100ms access decisions using local cache
- **Centralized Administration**: Flask-based web dashboard for user and card management
- **Cloud-Local Synchronization**: Automatic two-way sync between Supabase cloud and local SQLite databases
- **Real-Time Restrictions**: Supabase Realtime WebSocket propagates access blocks to field devices within 500ms
- **Offline Operation**: Local devices continue functioning independently if cloud connection is lost
- **Audit Trail**: Complete event logging of all access attempts (authorized and denied)
- **Role-Based Access**: Administrative interface restricts sensitive operations to authorized users
- **Multi-Room Support**: Block access by card and room combination for granular control

### Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Cloud Database | Supabase (PostgreSQL) | Authoritative data store, REST API |
| Realtime Communication | Supabase Realtime WebSocket | Push notifications to edge devices |
| Frontend Framework | Flask + Jinja2 | Web interface for administration |
| Authentication | Supabase Auth / JWT | User authentication and session management |
| Local Database | SQLite | Edge device cache and offline storage |
| Hardware Interface | GPIO (RPi.GPIO) | Relay control for door locks |
| Serial Communication | PySerial | UART communication with RFID readers |
| Background Tasks | Threading + exponential backoff | Worker for sync and Realtime listeners |

## Installation

### Prerequisites

- Python 3.8+
- Raspberry Pi 4+ (for field deployment) or Linux host
- Supabase project with configured authentication
- UART-connected RFID reader (e.g., Mifare reader)
- GPIO-controlled electronic lock

### Cloud Setup

1. Create a Supabase project
2. Execute the database schema (see `docs/diagramas/MODELO_DATOS_PLANTUML.md`)
3. Configure authentication with email/password
4. Enable Realtime for `access_blocks` table

### Frontend Installation

```bash
cd frontend
pip install -r requirements.txt
export SUPABASE_URL="https://your-project.supabase.co"
export SUPABASE_KEY="your-anon-public-key"
export SUPABASE_PASSWORD="your-service-role-password"
flask run
```

Access at `http://localhost:5000`

### Raspberry Pi Installation

```bash
cd raspberry
pip install -r requirements.txt
cp config.py.example config.py
# Edit config.py with your Supabase credentials
python main.py
```

The local server runs on port 5001 and the RFID reader/worker threads start automatically.

## Usage

### Administrative Dashboard

1. **Authentication**: Login with email/password (Supabase Auth)
2. **Card Management**: Create, edit, delete RFID cards and assign to users
3. **Access Control**: View access logs, filter by date/room/student
4. **Restrictions**: Block/unblock cards per room with reason tracking
5. **Infrastructure**: Manage buildings, rooms, and field devices

### Access Event Flow

```
1. Cardholder approaches RFID reader
   └─ UART transmits UID bytes

2. Raspberry Pi receives and parses UID
   └─ Queries local SQLite: is_card_blocked(card_uid, room_id)?

3. Decision made locally (<100ms):
   ├─ NOT blocked → GPIO relay activates → door unlocks
   └─ Blocked → No relay activation → access denied

4. Event recorded in local_events table
   └─ marked synced=0 (pending cloud sync)

5. Worker thread batch syncs events (~every 30s)
   └─ POST /rest/v1/access_events (batch insert to Supabase)
   └─ Updates synced=1 on successful response

6. Admin views event in dashboard access logs
   └─ Query includes room, building, and cardholder information
```

## API Endpoints

### Authentication

- `POST /` - Login (email, password)
- `POST /register` - Register new user (Supabase Auth)
- `POST /logout` - End session

### Dashboard

- `GET /dashboard` - Main dashboard with statistics
- `GET /access-logs` - Paginated access events with filters

### Card Management (Admin)

- `GET /manage-cards` - List all RFID cards
- `POST /add-card` - Create new card
- `POST /edit-card/<uid>` - Update card details
- `POST /delete-card/<uid>` - Remove card

### Access Control (Admin)

- `GET /blocked-cards` - View active restrictions
- `POST /block-card` - Restrict card in specific room
- `POST /unblock-card/<block_id>` - Remove restriction

### Infrastructure (Admin)

- `GET /buildings` - List all buildings
- `POST /add-building` - Create building
- `GET /rooms` - List all rooms
- `POST /add-room` - Create room
- `GET /spaces` - Unified view of buildings and rooms

### User Profile

- `GET /my-profile` - User profile and personal access history
- `GET /register` - Registration form

## Synchronization Architecture

### Cloud → Local (Real-Time, ~500ms)

**Trigger**: Admin blocks/unblocks card in web dashboard

```
1. Frontend POST /block-card → Flask backend
2. Flask inserts into access_blocks table
3. Supabase Realtime emits INSERT event on public:access_blocks channel
4. Raspberry Pi's Realtime listener receives event
5. Local upsert_blocked_card() updates SQLite blocked_cards
6. Next RFID read respects new block (or removal)
```

**Latency breakdown**:
- Web request: 50-100ms
- Database write: 10ms
- Realtime broadcast: 100-200ms
- Local update: <5ms
- **Total**: ~200-350ms (< 1s target)

### Local → Cloud (Background, ~30s intervals)

**Trigger**: Worker thread polls local_events for synced=0 rows

```
1. Worker queries SELECT * FROM local_events WHERE synced = 0
2. Validates card_uid exists in cloud rfid_cards (prevents FK violations)
3. Batches events into POST /rest/v1/access_events
4. On 201 success, marks rows with synced = 1
5. On failure, applies exponential backoff (1s, 2s, 4s, ..., max 120s)
6. Continues retrying until network restored
```

**Offline resilience**: Devices continue capturing and storing events. Automatic sync resumes when connectivity restored.

## Local Database Cache Strategy

### blocked_cards Cache

The `blocked_cards` SQLite table serves as a real-time cache:

- **Primary use**: Zero-latency access decisions during RFID reads
- **Update source**: Supabase Realtime (push-based)
- **Query pattern**: `SELECT 1 FROM blocked_cards WHERE card_uid = ? AND room_id = ?`
- **Performance**: Composite index lookup ~<1ms

### local_events Buffer

The `local_events` table buffers unsynced events:

- **Primary use**: Audit trail and sync queue
- **Storage**: Auto-incremented, timestamped rows
- **Cleanup**: Older synced rows optionally purged after 30 days
- **Validation**: `get_valid_unsynced_events()` filters invalid card UIDs

## Security Considerations

### Authentication

- Supabase Auth with JWT tokens
- Session-based for web dashboard (secure HTTP-only cookies)
- `is_admin` flag restricts sensitive endpoints (card creation, blocking, device registration)

### Data Validation

- All inputs sanitized and validated server-side
- SQL queries use parameterized statements (prevents injection)
- CSRF protection on POST endpoints
- Safe URL redirects validated against whitelist

### Network Security

- HTTPS enforced for web dashboard (configure in Flask production)
- Realtime WebSocket secured by Supabase (included)
- Local SQLite unencrypted (Raspberry Pi assumed physically secure)

### Access Control

- Role-based endpoints: `/manage-cards`, `/blocked-cards`, `/spaces` require `is_admin=true`
- `/my-profile` shows only user's own card and access history
- Flask `@_login_required` decorator enforces authentication on protected routes

## Configuration

### Frontend (flask)

Environment variables:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-public-key
SUPABASE_PASSWORD=your-service-role-password
```

### Raspberry Pi (edge device)

Edit `raspberry/config.py`:
```python
SUPABASE_URL = "https://your-project.supabase.co"
SUPABASE_KEY = "your-anon-key"
SUPABASE_EMAIL = "device-account@example.com"  # Service account
SUPABASE_PASSWORD = "service-account-password"
LOCAL_DB = "/var/local/tagpass.db"
SYNC_INTERVAL = 30  # seconds
GPIO_PIN = 17       # BCM pin for relay
UART_PORT = "/dev/ttyUSB0"
UART_BAUD = 9600
```

## Performance Specifications

### Access Decision Latency

- **RFID read to GPIO**: <100ms (local operations only)
- **Realtime block propagation**: 200-500ms (cloud to Raspberry)
- **Batch event sync**: 30-60s (background, non-blocking)

### Storage Requirements

- **Local SQLite**: <1MB typical (500-2000 pending events, 50-500 cached blocks)
- **Cloud PostgreSQL**: Scales with event volume (1+ year retention easily manageable at scale)

### Throughput

- **Per-device**: ~10 reads/second sustainable (single reader)
- **Per-facility**: Horizontal scaling via additional Raspberry Pi devices

## Monitoring and Debugging

### Local Device Status

Check device status via REST endpoint (local):
```bash
curl http://localhost:5001/status
```

Response includes:
- Unsynced event count
- Blocked card cache size
- Last sync timestamp
- Connection status

### Logs

- Frontend: Flask default logs (stdout)
- Raspberry Pi: Print statements to stdout (configure with systemd journal)
- Access events: Queryable via dashboard or direct SQL

### Common Issues

| Issue | Diagnosis | Resolution |
|-------|-----------|-----------|
| Events not syncing | Check `SELECT COUNT(*) WHERE synced=0` in local_events | Verify network connectivity, check Supabase API keys |
| Blocks not applied | Check `SELECT * FROM blocked_cards` on Raspberry | Verify Realtime listener active, check Supabase credentials |
| Slow access decisions | Monitor UART/GPIO timing | Reduce reader poll frequency or optimize local queries |
| High storage usage | Check local_events table size | Run cleanup: `DELETE WHERE synced=1 AND timestamp < datetime('now', '-30 days')` |

## Project Structure

```
TagPass-RFID-Access-Management/
├── frontend/                          # Flask web application
│   ├── app.py                        # Main Flask app with routes
│   ├── requirements.txt               # Python dependencies
│   ├── static/
│   │   ├── css/style.css              # Dashboard styles
│   │   └── js/dashboard.js            # Client-side scripts
│   └── templates/                    # Jinja2 templates
│       ├── layout.html               # Base template
│       ├── login.html                # Authentication
│       ├── dashboard.html            # Main dashboard
│       ├── manage_cards.html         # Card management
│       ├── blocked_cards.html        # Restrictions UI
│       ├── access_logs.html          # Audit trail
│       └── spaces.html               # Infrastructure UI
│
├── raspberry/                         # Edge device (Raspberry Pi)
│   ├── main.py                       # Entry point
│   ├── config.py                     # Configuration
│   ├── db_local.py                   # SQLite operations
│   ├── read_rfid.py                  # UART/RFID reader
│   ├── worker.py                     # Sync and Realtime listener
│   ├── local_server.py               # Status endpoint
│   ├── runtime_state.py              # Shared state
│   └── requirements.txt              # Python dependencies
│
├── docs/
│   └── diagramas/                    # Architecture and data model diagrams
│       ├── 1-modelo-datos/           # ER diagrams (Mermaid)
│       ├── 2-secuencias/             # Sequence diagrams
│       ├── MODELO_DATOS_PLANTUML.md  # Supabase schema (PlantUML)
│       ├── SECUENCIAS_DETALLADAS_PLANTUML.md  # Flows with functions
│       └── MODELO_DATOS_SQLITE_LOCAL.md      # Local SQLite schema
│
└── README.md                         # This file
```

## Development

### Local Testing

```bash
# Frontend
cd frontend
pip install -r requirements.txt
flask run  # Runs on http://localhost:5000

# Raspberry Pi (local simulation)
cd raspberry
pip install -r requirements.txt
python main.py  # Starts local server + worker threads
```

### Database Inspection

```bash
# Supabase CLI (optional)
supabase start
supabase db pull  # Generates local schema snapshot

# Direct SQLite inspection (Raspberry)
sqlite3 /var/local/tagpass.db
> SELECT COUNT(*) FROM local_events;
> SELECT COUNT(*) FROM blocked_cards;
```

## Contributing

1. Create feature branch: `git checkout -b feature/your-feature`
2. Commit changes: `git commit -am 'Add feature'`
3. Push to branch: `git push origin feature/your-feature`
4. Submit pull request with clear description

## License

[Specify your license here, e.g., MIT, Apache 2.0, GPL]

## Support

For issues, feature requests, or documentation improvements:
- Open an issue on GitHub
- Review architecture diagrams in `docs/diagramas/`
- Check configuration examples in `config.py.example`

## Acknowledgments

- Supabase team for PostgreSQL hosting and Realtime infrastructure
- Raspberry Pi community for GPIO and UART libraries
- Flask and Flask ecosystem contributors
