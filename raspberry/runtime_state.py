import threading
from typing import Optional

_lock = threading.Lock()
_device_id: Optional[str] = None
_room_id: Optional[str] = None


def set_device(device_id: Optional[str], room_id: Optional[str]):
    global _device_id, _room_id
    with _lock:
        _device_id = device_id
        _room_id = room_id


def update_room(room_id: Optional[str]):
    global _room_id
    with _lock:
        _room_id = room_id


def get_device_id() -> Optional[str]:
    with _lock:
        return _device_id


def get_room_id() -> Optional[str]:
    with _lock:
        return _room_id


def snapshot():
    with _lock:
        return {"device_id": _device_id, "room_id": _room_id}
