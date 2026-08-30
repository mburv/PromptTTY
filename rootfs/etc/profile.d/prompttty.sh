if [ "$(id -un 2>/dev/null)" = prompt ] && [ -d /home/prompt/workspace ]; then
    cd /home/prompt/workspace || true
fi

export PROMPTTTY_WORKSPACE="${PROMPTTTY_WORKSPACE:-/home/prompt/workspace}"
