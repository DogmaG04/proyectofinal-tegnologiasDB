# Documentación — Migración MySQL 5.7 → PostgreSQL 16

Rama `docs` del proyecto final de **Tecnología de Base de Datos I**
(Cooperativa de Ahorro y Crédito Horizonte PyME S.R.L.).

Esta rama contiene **solo la documentación**: el informe LaTeX, sus anexos,
figuras, evidencias y el guion de demostración. El código, los scripts, la
configuración Docker y las evidencias de ejecución están en la rama `dev`.

## Contenido

| Ruta | Descripción |
|------|-------------|
| `main.tex` | Punto de entrada del informe (datos del documento e `\input`). |
| `Makefile` | Compilación con `latexmk`. |
| `contenido/` | Capítulos I a VIII del informe. |
| `anexos/` | Anexos, incluye `codigo/` con fragmentos del proyecto. |
| `figuras/` | Capturas, diagramas y logo institucional. |
| `evidencias/` | Copias de las salidas reales de los scripts de auditoría, migración y verificación. |
| `formato/` | Plantilla UPDS: preámbulo APA, portada y bibliografía. |
| `GUION_DEMO_EN_VIVO.md` | Guion de la demostración en vivo. |
| `INSTALACION.md`, `DIAGRAMAS.md` | Guías de la plantilla LaTeX. |

## Compilación

Con TeX Live + `latexmk` instalados, desde la raíz de esta rama:

```bash
make          # genera main.pdf
make clean    # borra solo auxiliares
make cleanall # borra auxiliares y el PDF
```

Sin instalar nada en el host (usa la imagen `texlive/texlive`):

```bash
docker run --rm -v "$PWD:/docs" -w /docs texlive/texlive:latest make
```

Los archivos generados (`main.pdf`, `*.aux`, `*.log`, etc.) están excluidos del
control de versiones por `.gitignore`.

## Cambiar de rama

```bash
git checkout dev   # código y entorno
git checkout docs  # esta documentación
```
