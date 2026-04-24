# 🐧 Corbex-OS (Córdoba Excalibur Operating System)

> *"El año pasado customicé Linux Mint MATE para las notebooks escolares de las ESFP de Córdoba — equivalente a comprar un auto base y llevarlo al taller de tuning. Este año con CorbexOS, pedimos el auto customizado directamente desde la fábrica. ¡Pasamos del taller a la fábrica, papá!"*

CorbexOS no es un scriptcito más de post-configuración armado a las apuradas. Es una imagen ISO de **Devuan GNU/Linux (Excalibur)** construida *desde cero* y pensada con arquitectura pura para las netbooks de las escuelas secundarias de Córdoba. 

Acá no hay inmediatez ni atajos baratos: la ISO sale del horno con el sistema, el escritorio MATE, software educativo pesado, firmwares blindados (`hw-detect`), y la red preconfigurada. El técnico enchufa el USB, bootea, y la máquina se instala sola (100% desatendida) mientras se toma unos buenos mates. 

---

## 🏛️ ¿Por qué Devuan y no Ubuntu/Mint? (Conceptos > Código)

Las netbooks escolares son hardware acotado (típicamente 4GB de RAM y procesadores Celeron/Atom que piden auxilio). Instalarles un Ubuntu de fábrica con GNOME es la muerte.

Devuan corre sobre la gloria de **OpenRC** en lugar del monolítico systemd, lo que se traduce en un arranque rapidísimo, menos procesos en memoria y recursos reales para que el pibe pueda estudiar. El escritorio **MATE** completa la ecuación: liviano a más no poder, y con una curva de aprendizaje mínima para cualquiera que venga de Windows.

---

## 🚀 Qué trae CorbexOS bajo el capó

| Área | Arquitectura Detallada |
|---|---|
| **Motor (Base)** | Devuan Excalibur (Stable) — sin rastro de systemd. |
| **Arranque** | OpenRC con paralelismo optimizado. |
| **Interfaz** | MATE Desktop (Liviano y de la vieja escuela). |
| **Ofimática** | LibreOffice en español (es-AR). |
| **Programación** | Python 3, PSeInt, Git, Node.js (Herramientas para pensar). |
| **Diseño** | GIMP, Inkscape, Avidemux, Audacity. |
| **Navegador** | Google Chrome (con sync listo para cuentas escolares). |
| **IDE Educativo** | Antigravity (Instalación automática y offline). |
| **Drivers** | NetworkManager y blindaje de firmwares Intel/Realtek para bare-metal. |
| **Instalación** | Archivo `preseed.cfg` inyectado para un deploy desatendido, anti-errores y sin humanos en el medio. |
| **Idioma** | Español (Rioplatense / Argentina) de punta a punta. |

---

## 📂 Estructura Modular del Repositorio

Acá programamos dividiendo los problemas grandes en piezas chicas. Fijate el esquema:

```
corbex-os/
├── main.sh                  # Orquestador maestro — la batuta que dirige todo.
├── config.env               # Variables duras (rutas, de dónde bajar cosas).
├── preseed.cfg              # El cerebro desatendido: LVM, usuarios, GRUB.
├── rc.conf                  # Tweaks de OpenRC.
├── modules/                 # (Las tripas del build)
│   ├── 01_check_deps.sh     # Chequeo de dependencias vitales.
│   ├── 02_extract_iso.sh    # Operación a la ISO Netinstall base.
│   ├── 03_build_initrd.sh   # Cirugía mayor al initrd (inyección de preseed).
│   ├── 04_repo_local.sh     # Armado de repositorio offline de chapa y pintura.
│   └── 05_build_iso.sh      # El reensamblado magistral con xorriso.
├── scripts_aux/
│   └── postinst_final.sh    # Remate de configuración en el chroot del target.
├── templates/               # Plantillas estructurales (MATE, GRUB, ISOLINUX).
└── openspec/                # Infraestructura de Spec-Driven Development (SDD/ATL).
```
### 🪟 Usuarios de Windows (El camino del Arquitecto)

Ni te gastes intentando esto con MinGW, Git Bash o Cygwin. No estamos compilando un scriptcito; estamos forjando un sistema operativo. Para que la ISO mantenga los permisos de archivos correctos y las herramientas de Debian funcionen, necesitás un Linux real.

La forma profesional de hacerlo en Windows es con **WSL2 (Windows Subsystem for Linux)**:

1. **Instalá WSL2** (si no lo tenés):
   Abrí una PowerShell como Administrador y ejecutá:
   ```powershell
   wsl --install -d Debian
   ```
   *(Reiniciá la PC si te lo pide. No seas ansioso).*

2. **Prepará el entorno en WSL2:**
   Abrí la terminal de Debian que acabás de instalar y tirá este comando para tener todas las herramientas listas:
   ```bash
   sudo apt update && sudo apt install xorriso rsync cpio dpkg-dev mtools wget curl git
   ```

3. **Cloná y dale masa:**
   Ahora seguí las mismas instrucciones de build que figuran abajo, pero recordá hacerlo siempre **dentro** de tu terminal de WSL2.

---

## 🛠️ Cómo Compilar a esta Bestia

Si querés sentir la verdadera adrenalina y aprender cómo funciona esto, bajate el repo y compilá en tu propia consola. 

### Requisitos Previos

Necesitás las ISOs de Devuan Excalibur (Netinstall y Pool1) y las herramientas básicas en tu Linux:
```bash
sudo apt install xorriso cpio rsync wget curl dpkg-dev flatpak
```

### Instrucciones de Build

```bash
# 1. Clonás el repositorio a tu máquina
git clone https://github.com/mankeletor/corbex-os.git
cd corbex-os

# 2. Reconfigurás si es necesario
nano config.env

# 3. Le das masa al script como buen artesano del software
./main.sh
```

El proceso de forjado toma entre 15 y 40 minutos dependiendo de tu ancho de banda y la velocidad del espejo (mirror). Al final de la línea de ensamble, te escupe una ISO lista para quemar en un pendrive, con su `.md5` reglamentario.

---

## 📥 Descarga de la ISO Terminada

Si venís corto de tiempo o querés hacer deploy ya en el aula:

> 🚀 **[devuan-corbexos-20260424_1446.iso (MEGA)](https://mega.nz/file/HQNhFRTa#mb_GSOsTT307xc5GRQO9Pl-v-BOvWV8NJnljma67Nvc)** (untested)
>
> 📄 **[devuan-corbexos-20260424_1446.iso.md5 (MEGA)](https://mega.nz/file/rJlF3STR#8qBrjfQYnOiMkORubhQnHQCOqgUBa0Nnr-TcecHYpcc)**

Para quemarla en un pendrive:

*   **En Linux (a lo alfa):**
    ```bash
    sudo dd if=corbex-os.iso of=/dev/sdX bs=4M status=progress oflag=sync
    ```
    *(Cambiá `/dev/sdX` por tu USB. Un error acá y te borrás el disco de 1TB, ¡no digas que no te avisé!)* 

*   **En Windows:**
    Usá **[Rufus](https://rufus.ie/)** en modo "DD" (si te pregunta) para asegurar la compatibilidad con el esquema de particionado híbrido.

---

## 👤 Creador de la Criatura

**Pablo Saquilán (DJ Mankeletor)** — Maintainer, PM - Software Engineer - Senior Dev (según la IA porque andamos flojos de papeles) y profe de matemática.
📧 [psaquilan82@gmail.com](mailto:psaquilan82@gmail.com)

*Hecho desde las trincheras de la educación pública cordobesa para el mundo.*
