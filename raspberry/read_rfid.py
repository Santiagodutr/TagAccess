#!/usr/bin/env python3
import signal
import time
import requests
from pirc522 import RFID

BACKEND_URL = "http://localhost:5000/rfid"

rdr = RFID()
util = rdr.util()
util.debug = False

running = True

def end_read(signum, frame):
    global running
    print("\nDeteniendo lectura...")
    running = False
    try:
        rdr.cleanup()
    except Exception:
        pass

signal.signal(signal.SIGINT, end_read)

print("Acerca una tarjeta RFID...")

while running:
    try:
        (error, tag_type) = rdr.request()
        if error:
            time.sleep(0.1)
            continue

        (error, uid) = rdr.anticoll()
        if error:
            print("Error leyendo UID:", error)
            time.sleep(0.2)
            continue

        print("UID crudo:", uid)

        # ahora el UID se concatena tal cual, sin convertir a hex
        card_uid = "-".join(str(x) for x in uid)
        print("UID formateado:", card_uid)

        if not card_uid:
            print("UID vacio, ignorando.")
            time.sleep(0.2)
            continue

        payload = {"card_uid": card_uid}
        print("Payload a enviar:", payload)

        try:
            resp = requests.post(BACKEND_URL, json=payload, timeout=5)
            print("Respuesta backend:", resp.status_code, resp.text)
        except requests.RequestException as exc:
            print("Error enviando al backend:", exc)

        time.sleep(1)

    except KeyboardInterrupt:
        break
    except Exception as e:
        print("Error inesperado en loop:", e)
        time.sleep(0.5)

try:
    rdr.cleanup()
except Exception:
    pass

print("Programa finalizado.")
