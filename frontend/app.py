import os
from datetime import datetime
from functools import wraps
from typing import Any, Dict, Optional
from urllib.parse import urljoin, urlparse
from dotenv import load_dotenv
from flask import Flask, flash, redirect, render_template, request, session, url_for
from supabase import Client, create_client

load_dotenv()

ACCESS_LOGS_TABLE = os.getenv("ACCESS_LOGS_TABLE", "access_logs")
ACCESS_PERMISSIONS_TABLE = os.getenv(
    "ACCESS_PERMISSIONS_TABLE", "access_permissions"
)
ACCESS_LOGS_STUDENT_FIELD = os.getenv(
    "ACCESS_LOGS_STUDENT_FIELD", "student_name"
)
ACCESS_LOGS_ROOM_FIELD = os.getenv("ACCESS_LOGS_ROOM_FIELD", "room")
ACCESS_LOGS_BUILDING_FIELD = os.getenv(
    "ACCESS_LOGS_BUILDING_FIELD", "building"
)

def _create_supabase_client() -> Client:
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")

    if not url or not key:
        raise RuntimeError(
            "Missing SUPABASE_URL or SUPABASE_KEY environment variables."
        )

    return create_client(url, key)


def _login_required(view_func):
    @wraps(view_func)
    def wrapper(*args, **kwargs):
        if "user" not in session:
            flash("Por favor inicia sesión para continuar.", "warning")
            return redirect(url_for("login"))
        return view_func(*args, **kwargs)

    return wrapper


def _parse_date_filter(value: str, *, end_of_day: bool = False) -> Optional[str]:
    if not value:
        return None
    try:
        parsed = datetime.strptime(value, "%Y-%m-%d")
        if end_of_day:
            parsed = parsed.replace(hour=23, minute=59, second=59)
        return parsed.isoformat()
    except ValueError:
        return None


def _fetch_access_logs(client: Client, filters: Dict[str, Any]) -> Dict[str, Any]:
    try:
        query = client.table(ACCESS_LOGS_TABLE).select("*")

        if filters.get("student"):
            query = query.ilike(
                ACCESS_LOGS_STUDENT_FIELD, f"%{filters['student']}%"
            )
        if filters.get("room"):
            query = query.eq(ACCESS_LOGS_ROOM_FIELD, filters["room"])
        if filters.get("building"):
            query = query.eq(ACCESS_LOGS_BUILDING_FIELD, filters["building"])
        if filters.get("start_date"):
            query = query.gte("timestamp", filters["start_date"])
        if filters.get("end_date"):
            query = query.lte("timestamp", filters["end_date"])

        limit = filters.get("limit") or 50
        limit = max(1, min(limit, 500))
        response = (
            query.order("timestamp", desc=True).limit(limit).execute()
        )
        if getattr(response, "error", None):
            raise RuntimeError(response.error)
        return {"data": response.data or [], "error": None}
    except Exception as exc:  # pragma: no cover - safeguard for unexpected API errors
        raw_error = exc
        if isinstance(exc, RuntimeError) and exc.args:
            raw_error = exc.args[0]

        if isinstance(raw_error, dict):
            code = raw_error.get("code")
            message = raw_error.get("message") or str(raw_error)
            if code == "PGRST205":
                message = (
                    "No se encontró la tabla de registros. Configura la variable "
                    "ACCESS_LOGS_TABLE con el nombre correcto (por ejemplo, 'access_blocks')."
                )
        else:
            message = str(raw_error)

        return {"data": [], "error": message}


def _fetch_filter_options(client: Client) -> Dict[str, Any]:
    options: Dict[str, Any] = {
        "students": [],
        "rooms": [],
        "buildings": [],
    }

    field_map = {
        "students": ACCESS_LOGS_STUDENT_FIELD,
        "rooms": ACCESS_LOGS_ROOM_FIELD,
        "buildings": ACCESS_LOGS_BUILDING_FIELD,
    }

    for key, field in field_map.items():
        try:
            response = (
                client.table(ACCESS_LOGS_TABLE)
                .select(field, distinct=True)
                .order(field)
                .limit(500)
                .execute()
            )
            if getattr(response, "error", None):
                continue
            raw_values = [row.get(field) for row in response.data or []]
            cleaned_values = [
                str(value)
                for value in raw_values
                if value not in (None, "")
            ]
            options[key] = sorted(
                dict.fromkeys(cleaned_values), key=lambda item: item.lower()
            )
        except Exception:
            # Silently ignore; dropdowns fall back to manual entry if needed.
            continue

    return options


def _normalize_log_entry(entry: Dict[str, Any]) -> Dict[str, Any]:
    normalized = dict(entry)
    normalized["_student_label"] = (
        entry.get(ACCESS_LOGS_STUDENT_FIELD)
        or entry.get("student_name")
        or entry.get("user_name")
        or entry.get("student")
        or ""
    )
    normalized["_room_label"] = (
        entry.get(ACCESS_LOGS_ROOM_FIELD)
        or entry.get("room")
        or entry.get("salon")
        or ""
    )
    normalized["_room_value"] = (
        entry.get(ACCESS_LOGS_ROOM_FIELD)
        or entry.get("room")
        or entry.get("salon")
        or ""
    )
    normalized["_building_label"] = (
        entry.get(ACCESS_LOGS_BUILDING_FIELD)
        or entry.get("building")
        or entry.get("edificio")
        or ""
    )
    normalized["_building_value"] = (
        entry.get(ACCESS_LOGS_BUILDING_FIELD)
        or entry.get("building")
        or entry.get("edificio")
        or ""
    )
    normalized["_is_blocked"] = bool(entry.get("is_blocked"))
    return normalized


def _block_user_card(
    client: Client,
    *,
    uid: str,
    room: str,
    building: Optional[str],
    reason: Optional[str],
) -> None:
    payload: Dict[str, Any] = {
        "is_blocked": True,
        "blocked_at": datetime.utcnow().isoformat(),
    }
    if reason:
        payload["block_reason"] = reason

    update_query = client.table(ACCESS_PERMISSIONS_TABLE).update(payload).eq("uid", uid)
    if room:
        update_query = update_query.eq("room", room)
    if building:
        update_query = update_query.eq("building", building)

    response = update_query.execute()
    if getattr(response, "error", None):
        raise RuntimeError(response.error)
    if not response.data:
        upsert_payload = {
            **payload,
            "uid": uid,
            "room": room,
        }
        if building:
            upsert_payload["building"] = building
        upsert_response = (
            client.table(ACCESS_PERMISSIONS_TABLE)
            .upsert(upsert_payload)
            .execute()
        )
        if getattr(upsert_response, "error", None):
            raise RuntimeError(upsert_response.error)


def _is_safe_redirect(target: str) -> bool:
    if not target:
        return False
    ref_url = urlparse(request.host_url)
    test_url = urlparse(urljoin(request.host_url, target))
    return (
        test_url.scheme in {"http", "https"}
        and ref_url.netloc == test_url.netloc
    )


def create_app(existing_supabase: Optional[Client] = None) -> Flask:
    app = Flask(__name__)
    app.secret_key = os.getenv("FLASK_SECRET_KEY", "change-me")
    app.supabase = existing_supabase

    @app.before_request
    def ensure_supabase_client() -> None:
        if app.supabase is None:
            app.supabase = _create_supabase_client()

    @app.route("/", methods=["GET", "POST"])
    def login():
        if request.method == "POST":
            email = request.form.get("email", "").strip()
            password = request.form.get("password", "")

            if not email or not password:
                flash("Correo y contraseña son obligatorios.", "danger")
                return render_template("login.html")

            try:
                assert app.supabase is not None
                auth_response = app.supabase.auth.sign_in_with_password(
                    {"email": email, "password": password}
                )
                user = getattr(auth_response, "user", None)
                if not user:
                    raise ValueError("No se pudo recuperar la información del usuario.")

                session["user"] = {
                    "id": user.id,
                    "email": user.email,
                }
                flash("Inicio de sesión exitoso.", "success")
                return redirect(url_for("dashboard"))
            except Exception:
                flash("Credenciales inválidas o error de autenticación.", "danger")

        if "user" in session:
            return redirect(url_for("dashboard"))

        return render_template("login.html")

    @app.route("/dashboard")
    @_login_required
    def dashboard():
        assert app.supabase is not None
        limit_arg = request.args.get("limit", "").strip()
        try:
            parsed_limit = int(limit_arg) if limit_arg else 0
        except ValueError:
            flash("El límite debe ser un número entero.", "danger")
            parsed_limit = 0

        raw_filters = {
            "student": request.args.get("student", "").strip(),
            "room": request.args.get("room", "").strip(),
            "building": request.args.get("building", "").strip(),
            "limit": parsed_limit,
        }

        start_iso = _parse_date_filter(request.args.get("start_date", ""))
        end_iso = _parse_date_filter(
            request.args.get("end_date", ""), end_of_day=True
        )
        filters = {**raw_filters, "start_date": start_iso, "end_date": end_iso}
        logs_result = _fetch_access_logs(app.supabase, filters)
        normalized_logs = [_normalize_log_entry(row) for row in logs_result["data"]]
        filter_options = (
            _fetch_filter_options(app.supabase)
            if logs_result["error"] is None
            else {"students": [], "rooms": [], "buildings": []}
        )
        def _distinct(values):
            cleaned = []
            for item in values:
                value = "" if item is None else str(item).strip()
                if value:
                    cleaned.append(value)
            return sorted(
                dict.fromkeys(cleaned), key=lambda item: item.lower()
            )

        if not filter_options["students"]:
            filter_options["students"] = _distinct(
                [log.get("_student_label") for log in normalized_logs]
            )
        if not filter_options["rooms"]:
            filter_options["rooms"] = _distinct(
                [log.get("_room_label") for log in normalized_logs]
            )
        if not filter_options["buildings"]:
            filter_options["buildings"] = _distinct(
                [log.get("_building_label") for log in normalized_logs]
            )
        filter_defaults = {
            "student": raw_filters["student"],
            "room": raw_filters["room"],
            "building": raw_filters["building"],
            "start_date": request.args.get("start_date", ""),
            "end_date": request.args.get("end_date", ""),
            "limit": limit_arg or (raw_filters["limit"] or ""),
        }
        return render_template(
            "dashboard.html",
            user=session.get("user"),
            logs=normalized_logs,
            logs_error=logs_result["error"],
            filters=filter_defaults,
            filter_options=filter_options,
        )

    @app.route("/logout")
    def logout():
        session.pop("user", None)
        flash("Sesión cerrada correctamente.", "info")
        return redirect(url_for("login"))

    @app.route("/block-access", methods=["POST"])
    @_login_required
    def block_access():
        uid = request.form.get("uid", "").strip()
        room = request.form.get("room", "").strip()
        building = request.form.get("building", "").strip()
        reason = request.form.get("reason", "").strip()
        student = request.form.get("student", "").strip()
        next_url = request.form.get("next", "")

        if not uid or not room:
            flash(
                "Se requieren al menos el UID y el salón para bloquear una tarjeta.",
                "danger",
            )
            fallback = next_url if _is_safe_redirect(next_url) else url_for("dashboard")
            return redirect(fallback)

        try:
            assert app.supabase is not None
            _block_user_card(
                app.supabase,
                uid=uid,
                room=room,
                building=building or None,
                reason=reason or None,
            )
            flash(
                f"Tarjeta {uid} bloqueada para {student or 'el usuario'} en el salón {room}.",
                "success",
            )
        except Exception as exc:
            flash(f"No fue posible bloquear la tarjeta: {exc}", "danger")

        fallback = next_url if _is_safe_redirect(next_url) else url_for("dashboard")
        return redirect(fallback)

    return app


app = create_app()


if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))
    app.run(host="0.0.0.0", port=port, debug=os.getenv("DEBUG", "false").lower() == "true")
