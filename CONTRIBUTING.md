# Guía de Contribución Digna — CorbexOS 📀🇦🇷

Si aterrizaste acá es porque te interesó el código y querés ensuciarte las manos. Primero que nada: ¡bienvenido y mil gracias! CorbexOS es un esfuerzo gigantesco a pulmón para que los pibes de las escuelas de Córdoba arranquen con un sistema digno de uso diario. No queremos que un profe o un técnico se pase horas configurando netbooks a pedal. 

Pero ojo: **acá la filosofía manda**. Acá los conceptos están por encima del código facilista. No aceptamos pull requests tirados a las apuradas por alguien que no entiende cómo funciona la ISO por abajo.

---

## 🏛️ Filosofía del Proyecto: Conceptos > Código

1. **AI IS A TOOL: We direct, AI executes. The human always leads.** Si usás IA para programar, tenés que entender el código línea por línea. No copypastees bloques sin saber cómo pegan en el `preseed` o en el `chroot`. 
2. **KISS y Modularidad**. El orquestador es `main.sh`. Todo lo demás son piezas de relojería (`01_check_deps.sh`, `03_build_initrd.sh`, etc). Si vas a arreglar algo de LVM, no me toques el script de descargas. Cada script hace UNA sola cosa bien hecha.
3. **SDD (Spec-Driven Development)**: Cuidado con la inmediatez de los "fixes rápidos". Usamos la arquitectura temporal de `openspec/`. Todo feature nuevo tiene que arrancar proponiendo una fase de diseño.

---

## 🚀 Cómo Empezar a Laburar

### Herramientas del Entorno

Básicamente, necesitás una distro piola basada en Debian con todo el herramental encima:

```bash
sudo apt install xorriso cpio rsync wget curl dpkg-dev flatpak shellcheck qemu-system-x86
```

Vas a necesitar mínimo **10GB de espacio de disco duro** libres para que la ISO compile sin llorar por I/O disk full.

### Tu Primer Build (Clase Práctica)

```bash
git clone https://github.com/mankeletor/corbex-os.git
cd corbex-os
cp config.env.example config.env
# Abrí y configurá las rutas apuntando a tus ISOs Netinstall base.
nano config.env   
```

---

## 🛠️ Reglas Básicas de la Casa

1. **No se toca `main.sh`** a menos que tengas un motivo arquitectónico gigante para alterar el flujo.
2. **Funcionalidades Nuevas** → Script nuevo en `/modules/` (ej: `06_nuevo_feature.sh`) y enganchado prolijamente en el main.
3. **Escritorio MATE y Entorno** → Todo el "tuneo" de dconf va a `templates/corbex.dconf` o inyectado vía `scripts_aux/postinst_final.sh`.
4. **Instalación Offline de Software Extra** (Como PSeInt o Chrome, que no son paquetes oficiales puritanos) → Fijate el hermoso patrón que usamos: descargar el binario en `04_repo_local.sh`, y luego mandarle el comando de instalación silenciosa en `postinst_final.sh`. Seguí esa misma línea conceptual para todo software nuevo.

---

## 🧪 Pruebas Obligatorias (Tu red de seguridad)

Acá "en la cancha se ven los pingos". No me subas nada que no hayas probado con paciencia primero.

**Paso 1: Check de Sintaxis (Linting)**
```bash
shellcheck modules/*.sh scripts_aux/postinst_final.sh
```
*(Si shellcheck llora, vos corregís. Esa herramienta te salva de horas de debug).*

**Paso 2: Generar la bestia**
```bash
sudo bash main.sh
```

**Paso 3: Laboratorio QEMU**
```bash
qemu-system-x86_64 -cdrom /ruta/a/corbex-os.iso -m 2048 -boot d
```
Arrancá la ISO en máquina virtual y simulá la instalación desatendida entera. Asegurate de que el usuario `alumno` loguee perfecto.

---

## 📬 Protocolo para Contribuir

1. Hacé un Fork de este repositorio con ganas.
2. Ramificá descriptivamente. Nada de `mi-rama-test`.
   ```bash
   git checkout -b fix/audio-intel-hda
   git checkout -b feat/agregar-software-nuevo
   ```
3. Commits con peso semántico y fundamento técnico:
   * **MAL:** `Arreglo en red`.
   * **BIEN:** `fix: corregir inyección de locales en postinst_final.sh que causaba pantalla negra`.
   * **BIEN:** `refactor: simplificar discovery de mirror en modules para optimizar build`.
4. Clavá el Pull Request detallando EXACTAMENTE en qué entorno lo probaste (QEMU, Bare-Metal, USB de 16GB, etc.).

---

## 🎯 Se Buscan Arquitectos Para...

Si querés darle amor al repo, estas son las batallas que todavía estamos peleando:

- **Audio de las Netbooks Juana Manso**: Falla crónicamente con bajos niveles de audio debido a los Intel HDA. Se necesita código en `postinst` para tunear los perfiles ALSA predeterminados.
- **Gestión de Energía**: Baterías que mueren en 2 horas en el aula. Necesitamos perfilar TLP o acpi-cpufreq.
- **Branding de Arranque**: El splash de GRUB/ISOLINUX en texto es retro, sí, pero capaz un PNG de 640x480 de CorbexOS le da más chapa al instalador.
- **Scripts de Auto-Test Automáticos**: Algún loco de la automatización que monte un github-action con QEMU headless para que pruebe el boot ciego cada vez que hacés un commit.

---

## ⚖️ Licencia
Al mandar tu PR y colaborar con CorbexOS, aceptás con honores que tu código pasa a ser libre bajo **GNU GPL v3**. La educación es abierta, tu código también.
