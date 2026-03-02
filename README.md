# 🐧 Devuan ESFP Córdoba Edition (Excalibur)

Este proyecto contiene las herramientas y scripts necesarios para generar una imagen ISO personalizada de **Devuan GNU/Linux (Excalibur)**, optimizada específicamente para las netbooks de la **Escuela Secundaria de Formación Profesional (ESFP) Córdoba**.

---

## 🚀 Características Principales

- **Base:** Devuan Excalibur (Stable) — ¡Libre de Systemd!
- **Sistema de Init:** OpenRC con arranque paralelo optimizado.
- **Escritorio:** MATE Desktop liviano, ideal para equipos con 4 GB de RAM.
- **Automatización:** Instalación desatendida mediante `preseed.cfg`.
- **Software incluido:** Repositorio local integrado con suites de oficina, diseño (GIMP, Audacity) y herramientas de programación (Python, Git).
- **Optimización:** Swappiness reducido, autologin configurado y limpieza de servicios innecesarios para mejorar el rendimiento.

---

## 📂 Estructura del Repositorio

```
devuan-esfp-cordoba/
├── main.sh              # Script principal de customización de la ISO
├── postinst.sh          # Script de post-instalación (escritorio y optimizaciones)
├── preseed.cfg          # Respuestas automáticas para el instalador Debian/Devuan
├── rc.conf              # Ajustes para el arranque con OpenRC
├── config.env           # Variables de configuración del proyecto
├── pkgs_manual.txt      # Paquetes a instalar manualmente
├── pkgs_offline.txt     # Paquetes incluidos en el repositorio local (offline)
├── modules/             # Módulos auxiliares del script principal
├── scripts_aux/         # Scripts auxiliares de soporte
├── templates/           # Plantillas de configuración
└── obsolete/            # Archivos en desuso (no utilizar)
```

---

## 🛠️ Cómo Construir la ISO

### Requisitos Previos

1. **ISO Netinstall de Devuan Excalibur:**
   ```
   https://mirror.leaseweb.com/devuan/devuan_excalibur/installer-iso/devuan_excalibur_6.1.0_amd64_netinstall.iso
   ```

2. **ISO Pool1 de Devuan** (necesaria para el repositorio local offline):
   ```
   https://mirror.leaseweb.com/devuan/devuan_excalibur/installer-iso/devuan_excalibur_6.1.0_amd64_pool1.iso
   ```

3. **Dependencias del sistema:**
   ```bash
   sudo apt install xorriso cpio rsync isolinux
   ```

### Instrucciones

1. Clonar este repositorio:
   ```bash
   git clone https://github.com/mankeletor/devuan-esfp-cordoba.git
   cd devuan-esfp-cordoba
   ```

2. Editar `config.env` con las rutas correctas a las ISOs descargadas:
   ```bash
   nano config.env
   ```

3. Ejecutar el script principal como root:
   ```bash
   sudo bash main.sh
   ```

---

## 📥 Descarga de la ISO Lista para Usar

Si no querés compilar la ISO por tu cuenta, podés descargar la versión estable y lista para grabar en un USB:

> ⚠️ **Enlace de descarga próximamente disponible.**

### ✅ Verificación de Integridad

Una vez descargada la ISO, verificá que no esté corrupta con el archivo `.sha256` incluido:

```bash
sha256sum -c devuan-esfp-cordoba.iso.sha256
```

### 💾 Grabar en USB

```bash
sudo dd if=devuan-esfp-cordoba.iso of=/dev/sdX bs=4M status=progress && sync
```

> ⚠️ Reemplazá `/dev/sdX` con el dispositivo correcto (verificá con `lsblk` antes de ejecutar).

---

## 👤 Autor

**Pablo Saquilán** — Maintainer & Dev
📧 [psaquilan82@gmail.com](mailto:psaquilan82@gmail.com)

---

*Hecho para la educación técnica de Córdoba.*