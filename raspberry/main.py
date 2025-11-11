import threading
from db_local import init_local_db
from local_server import run_server
from worker import run_worker
from config import LOCAL_DB

if __name__ == "__main__":
    print("🚀 Iniciando Raspberry Local Server + Worker...")
    init_local_db(LOCAL_DB)

    t1 = threading.Thread(target=run_server, daemon=True)
    t2 = threading.Thread(target=run_worker, daemon=True)

    t1.start()
    t2.start()

    t1.join()
    t2.join()
