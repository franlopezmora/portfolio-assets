#!/usr/bin/env bash
set -euo pipefail

# ========= Uso =========
# ./make_push_project.sh <proyecto-slug> [input_dir] [branch] [commit_msg]
# Ej: ./make_push_project.sh vanish-input ../Videos/a-subir main "add vanish-input demo"
# =======================

# -------- Params --------
PROJ_RAW="${1:-}"
if [ -z "$PROJ_RAW" ]; then
  echo "Falta el <proyecto-slug>. Ej: ./make_push_project.sh vanish-input" >&2
  exit 1
fi

INPUT_DIR="${2:-../Videos/a-subir}"
BRANCH="${3:-main}"
COMMIT_MSG="${4:-add web demo}"

# slugificar el proyecto por si viene raro
PROJ_SLUG="$(echo "$PROJ_RAW" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g;s/^-+|-+$//g')"
SUBDIR="videos/${PROJ_SLUG}"

FPS=60
# ------------------------

# deps
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg no está instalado. Instala con: brew install ffmpeg" >&2
  exit 1
fi
if [ ! -d ".git" ]; then
  echo "Ejecutá este script dentro del repo portfolio-assets (donde está el .git)." >&2
  exit 1
fi

# remote → user/repo para jsDelivr
REMOTE_URL="$(git remote get-url origin)"
if [[ "$REMOTE_URL" =~ github.com[:/]+([^/]+)/([^/.]+) ]]; then
  GH_USER="${BASH_REMATCH[1]}"
  GH_REPO="${BASH_REMATCH[2]}"
else
  echo "No pude parsear el remote origin: $REMOTE_URL" >&2
  exit 1
fi

# buscar el .mov más reciente en INPUT_DIR
shopt -s nullglob
MOVS=("$INPUT_DIR"/*.mov "$INPUT_DIR"/*.MOV)
if [ ${#MOVS[@]} -eq 0 ]; then
  echo "No encontré .mov en: $INPUT_DIR" >&2
  exit 1
fi

# elegir el más reciente por fecha de modificación
LATEST_MOV="$(ls -t "${MOVS[@]}" 2>/dev/null | head -n1)"
if [ -z "$LATEST_MOV" ]; then
  echo "No pude determinar el .mov más reciente." >&2
  exit 1
fi
echo "→ Proyecto: $PROJ_SLUG"
echo "→ Usando fuente: $LATEST_MOV"

# crear subdirectorio del proyecto
mkdir -p "$SUBDIR"

# nombres fijos según proyecto
MP4_PATH="${SUBDIR}/${PROJ_SLUG}.mp4"
WEBM_PATH="${SUBDIR}/${PROJ_SLUG}.webm"
POSTER_PATH="${SUBDIR}/${PROJ_SLUG}-poster.jpg"

# convertir (sin reescalar, solo fps)
echo "   • Generando MP4"
ffmpeg -y -i "$LATEST_MOV" \
  -vf "fps=${FPS}" \
  -c:v libx264 -crf 23 -preset veryfast -movflags +faststart -pix_fmt yuv420p \
  -an "$MP4_PATH" >/dev/null 2>&1

echo "   • Generando WebM"
ffmpeg -y -i "$LATEST_MOV" \
  -vf "fps=${FPS}" \
  -c:v libvpx-vp9 -b:v 0 -crf 34 -row-mt 1 -deadline good \
  -an "$WEBM_PATH" >/dev/null 2>&1

echo "   • Generando poster"
ffmpeg -y -ss 0.5 -i "$LATEST_MOV" -vframes 1 "$POSTER_PATH" >/dev/null 2>&1

# push
git checkout "$BRANCH" >/dev/null 2>&1 || git checkout -b "$BRANCH"
git add "$SUBDIR"
git commit -m "$COMMIT_MSG" || true
git push origin "$BRANCH"

# URLs jsDelivr
BASE_CDN="https://cdn.jsdelivr.net/gh/${GH_USER}/${GH_REPO}@${BRANCH}/${SUBDIR}"
MP4_URL="${BASE_CDN}/${PROJ_SLUG}.mp4"
WEBM_URL="${BASE_CDN}/${PROJ_SLUG}.webm"
POSTER_URL="${BASE_CDN}/${PROJ_SLUG}-poster.jpg"

# título “humano” desde el slug
TITLE="$(echo "$PROJ_SLUG" | sed -E 's/-/ /g; s/\b(.)/\u\1/g')"

# snippet para Home.jsx
read -r -d '' SNIPPET <<EOF || true
{
  titulo: "${TITLE}",
  descripcion: "",
  gif: "${MP4_URL}",
  webm: "${WEBM_URL}",
  poster: "${POSTER_URL}",
  prototype: "/prototype/" // ← completá el número
}
EOF

echo
echo "✔ Listo. Archivos en: $SUBDIR"
echo
echo "🔗 URLs:"
echo "  MP4:    $MP4_URL"
echo "  WebM:   $WEBM_URL"
echo "  Poster: $POSTER_URL"
echo
echo "📦 Snippet para Home.jsx:"
echo "$SNIPPET"
echo
echo "Tip: si no ves cambios por cache, agregá '?v=\$(date +%s)' al final de la URL."
