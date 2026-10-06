# indiserver and INDI's simulator drivers, from the official INDI PPA
# (https://launchpad.net/~mutlaqja/+archive/ubuntu/ppa). The PPA only keeps
# its latest build, so the INDI version is whatever is current when the
# image is built: `dpkg-query -W indi-bin` in the image shows it.
#
# The PPA builds INDI 2.x only for recent Ubuntu releases. Where it has no
# build, apt silently installs Ubuntu's own INDI 1.9.9 instead (as on 24.04),
# so the base image follows the PPA and the build fails on INDI 1.x.
FROM ubuntu:26.04

LABEL org.opencontainers.image.source="https://github.com/torresj/indi-server-simulator-chart" \
      org.opencontainers.image.description="indiserver with INDI's simulator drivers"

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates gnupg software-properties-common \
    && add-apt-repository -y ppa:mutlaqja/ppa \
    && apt-get install -y --no-install-recommends indi-bin \
    && version="$(dpkg-query -W -f='${Version}' indi-bin)" \
    && if dpkg --compare-versions "$version" lt 2; then \
         echo "indi-bin $version is Ubuntu's INDI 1.x, not the INDI PPA's 2.x" >&2; exit 1; \
       fi \
    && apt-get purge -y --auto-remove gnupg software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Drivers keep their configuration in ~/.indi.
RUN groupadd --gid 10001 indi \
    && useradd --uid 10001 --gid indi --create-home --home-dir /home/indi --shell /usr/sbin/nologin indi

USER 10001:10001
ENV HOME=/home/indi
WORKDIR /home/indi

EXPOSE 7624

# The chart replaces CMD with the flags and drivers from its values.
ENTRYPOINT ["indiserver"]
CMD ["-v", "indi_simulator_telescope", "indi_simulator_ccd", "indi_simulator_focus", "indi_simulator_wheel"]
