# x11docker/xserver
#
# Internal use of x11docker to run X servers in container
# Used automatically by x11docker if image is available locally.
# Can be configured with option --xc.
#
# Build image with: podman build -t x11docker/xserver .
# The build will take a while because nxagent is compiled from source.
#
# x11docker on github: https://github.com/mviereck/x11docker

#########################

# build patched nxagent from source. Allows to run with /tmp/.X11-unix not to be owned by root.
# https://github.com/ArcticaProject/nx-libs/issues/1034
FROM docker.io/ubuntu:latest AS builder
RUN <<EOF
sed -i 's/Types: deb/\0 deb-src/g' /etc/apt/sources.list.d/ubuntu.sources
DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y build-essential devscripts
apt-get build-dep -y nxagent
mkdir /nxbuild
cd /nxbuild
apt-get source nxagent
cd nx-libs-*
sed -i 's/# define XtransFailSoft NO/# define XtransFailSoft YES/' nx-X11/config/cf/X11.rules
debuild -b -uc -us
EOF

# compile fake MIT-SHM library
COPY XlibNoSHM.c /XlibNoSHM.c
RUN <<EOF
env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    gcc \
    libc6-dev \
    libx11-dev
gcc -shared -o /XlibNoSHM.so /XlibNoSHM.c
EOF

#########################

FROM docker.io/ubuntu:latest
COPY --from=builder /nxbuild/nxagent_*.deb /nxagent.deb
COPY --from=builder /XlibNoSHM.so /XlibNoSHM.so

# update apt cache
RUN env DEBIAN_FRONTEND=noninteractive apt-get update

# install nxagent
RUN env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /nxagent.deb

# X servers
RUN env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        kwin-wayland \
        kwin-wayland-backend-drm \
        kwin-wayland-backend-wayland \
        kwin-wayland-backend-x11 \
        weston \
        xserver-xephyr \
        xserver-xorg \
        xserver-xorg-legacy \
        xvfb \
        xwayland

# xpra
RUN env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        xpra  \
        ibus \
        python3-rencode

# Window manager openbox with disabled context menu
RUN <<EOF
env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openbox
sed -i /ShowMenu/d         /etc/xdg/openbox/rc.xml
sed -i s/NLIMC/NLMC/       /etc/xdg/openbox/rc.xml
EOF

# tools
RUN env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        catatonit \
        procps \
        psmisc \
        psutils \
        socat \
        vainfo \
        vdpauinfo \
        virgl-server \
        wl-clipboard \
        wmctrl \
        x11-utils \
        x11-xkb-utils \
        x11-xserver-utils \
        xauth \
        xbindkeys \
        xclip \
        xdotool \
        xfishtank \
        xinit

# cleanup
RUN <<EOF
env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
apt-get clean
find /var/lib/apt/lists -type f -delete
find /var/cache -type f -delete
find /var/log -type f -delete
EOF

# configure Xorg wrapper
RUN echo 'allowed_users=anybody' > /etc/X11/Xwrapper.config && \
    echo 'needs_root_rights=yes' >> /etc/X11/Xwrapper.config

# wrapper to run weston either on console or within DISPLAY or WAYLAND_DISPLAY
# note: includes setuid for agetty to allow it for unprivileged users
RUN echo '#! /bin/bash \n\
case "$DISPLAY$WAYLAND_DISPLAY" in \n\
  "") \n\
    [ -e /dev/tty$XDG_VTNR ] && [ -n "$XDG_VTNR" ] || { \n\
      echo "ERROR: No display and no tty found. XDG_VTNR is empty." >&2 \n\
      exit 1 \n\
    } \n\
    exec agetty --login-options "-v -- $* --log=/x11docker/compositor.log " --autologin $(id -un) --login-program /usr/bin/weston-launch --noclear tty$XDG_VTNR \n\
  ;; \n\
  *) \n\
    exec /usr/bin/weston "$@" \n\
  ;; \n\
esac \n\
' > /usr/local/bin/weston && \
    chmod +x /usr/local/bin/weston && \
    ln /usr/local/bin/weston /usr/local/bin/weston-launch

# HOME
RUN mkdir -p /home/container && chmod 777 /home/container
ENV HOME=/home/container

LABEL version='2.0'
LABEL options='--kwin --nxagent --weston --weston-xwayland --xephyr --xpra --xpra-xwayland --xpra2 --xpra2-xwayland --xorg --xvfb --xwayland'
LABEL tools='catatonit cvt glxinfo iceauth setxkbmap socat \
             vainfo vdpauinfo virgl wl-copy wl-paste wmctrl \
             xauth xbindkeys xclip xdotool xdpyinfo xdriinfo xev \
             xfishtank xhost xinit xkbcomp xkill xlsclients xmessage \
             xmodmap xprop xrandr xrefresh xset xsetroot xvinfo xwininfo'
LABEL options_console='--kwin --weston --weston-xwayland --xorg'
LABEL gpu='MESA'
LABEL windowmanager='openbox'

ENTRYPOINT ["/usr/bin/catatonit", "--"]
