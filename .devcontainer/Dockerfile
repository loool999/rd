FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates gnupg && \
    add-apt-repository -y universe && \
    add-apt-repository -y multiverse && \
    add-apt-repository -y ppa:mozillateam/ppa && \
    printf 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' \
        > /etc/apt/preferences.d/mozilla-firefox && \
    apt-get update

RUN apt-get install -y \
    xvfb x11vnc dbus dbus-x11 at-spi2-core \
    x11-utils x11-xserver-utils xdg-utils xdg-user-dirs \
    python3 python3-pip python3-numpy \
    procps net-tools iproute2 \
    git curl wget sudo locales && \
    locale-gen en_US.UTF-8

RUN pip3 install --no-cache-dir aiohttp numpy

RUN apt-get install -y xfce4 xfce4-goodies

RUN apt-get install -y \
    arc-theme papirus-icon-theme adwaita-icon-theme \
    gnome-themes-extra gtk2-engines-murrine gtk2-engines-pixbuf \
    breeze-cursor-theme || true

RUN apt-get install -y \
    fonts-dejavu fonts-liberation fonts-liberation2 \
    fonts-noto fonts-noto-color-emoji \
    fonts-ubuntu fonts-firacode fonts-hack

RUN apt-get install -y firefox

RUN apt-get install -y \
    libreoffice-writer libreoffice-calc \
    libreoffice-impress libreoffice-draw \
    libreoffice-gtk3

RUN apt-get install -y \
    thunar thunar-archive-plugin thunar-volman \
    gvfs gvfs-backends tumbler ffmpegthumbnailer \
    file-roller zip unzip p7zip-full

RUN apt-get install -y mousepad geany geany-plugins nano vim
RUN apt-get install -y ristretto eog evince vlc mpv

RUN apt-get install -y \
    gnome-calculator gnome-system-monitor \
    baobab htop neofetch tilix

RUN apt-get install -y \
    build-essential gcc g++ make cmake \
    python3-venv nodejs npm imagemagick

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8