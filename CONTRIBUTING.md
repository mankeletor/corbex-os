# Guía de Contribución - CorbexOS ISO Customizer 📀🇦🇷

¡Gracias por interesarte en mejorar la netbook escolar! Este proyecto busca crear una imagen de Devuan optimizada, ligera y 100% automatizada.

## 🚀 Cómo empezar

### 1. Requisitos previos
Para colaborar en el desarrollo, necesitás un entorno Linux (preferentemente Debian/Devuan) con:
*   `xorriso`, `squashfs-tools`, `cpio`, `wget`.
*   `QEMU` para las pruebas de booteo.
*   Al menos 10GB de espacio libre en disco.

### 2. Clonar y Configurar
1.  Cloná el repositorio.
2.  Copiá el archivo de ejemplo: `cp config.env.example config.env`.
3.  Editá `config.env` con las rutas locales de tus ISOs base.

## 🛠️ Estructura de Trabajo
El proyecto es Modular (KISS). No edites el `main.sh` a menos que sea necesario cambiar el flujo principal.

*   **Módulos (`/modules`)**: Cada script debe encargarse de una sola tarea (ej. extraer, inyectar, compilar). Si querés agregar una funcionalidad, creá un script `06_nombre.sh` y registralo en `main.sh`.
*   **Plantillas (`/templates`)**: Aquí viven el `preseed.cfg` y el `postinst.sh`. Cualquier cambio en la configuración del escritorio MATE debe ir en `postinst.sh`.

## 🧪 Ciclo de Pruebas (Testing)
Antes de enviar un cambio, por favor verificá:
1.  **Sintaxis**: Corré `shellcheck` sobre tus scripts de Bash.
2.  **Booteo**: Generá la ISO y probala en QEMU.
3.  **Paquetes**: Verificá que la lista en `pkgs.txt` no tenga dependencias rotas que detengan el instalador.

## 📬 Cómo enviar tus mejoras
1.  Fork el proyecto.
2.  Creá una rama (branch) para tu mejora: `git checkout -b mejora-sonido-intel`.
3.  Hacé el Commit: Sé descriptivo (ej: `fix: corregir inyección de locales en postinst.sh`).
4.  Abrí un Pull Request.

### Áreas prioritarias para colaborar:
*   🔊 **Audio**: Mejora de los scripts de amplificación para hardware específico de netbooks Juana Manso / Conectar Igualdad.
*   🔋 **Energía**: Optimización de consumo de batería en OpenRC.
*   🎨 **Branding**: Arte visual de Corbex para el cargador de arranque (ISOLINUX).

## ⚖️ Licencia
Al contribuir, aceptás que tu código será liberado bajo la licencia **GNU GPL v3**.
