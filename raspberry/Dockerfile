FROM python:3.11-slim

# Nota: Esta imagen funciona en múltiples arquitecturas (incluyendo ARM). Para
# construir en una Raspberry Pi (32-bit) usa buildx o construye directamente en
# la Pi. Ejemplo (desde una máquina x86 -> Pi 32-bit):
#   docker buildx build --platform linux/arm/v7 -t tagpass-rfid -f raspberry/Dockerfile .

ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Dependencias del sistema comunes en Raspberry
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
	   build-essential gcc libffi-dev libssl-dev pkg-config ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

# Copia e instala los requisitos
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copia el resto de la aplicación
COPY . .

# Crear un usuario no-root para ejecutar la aplicación
RUN groupadd -r app && useradd -r -g app app \
	&& chown -R app:app /app

USER app

# Ejecuta main.py por defecto
CMD ["python", "main.py"]

