FROM buildpack-deps:xenial-curl

MAINTAINER vicamo@gmail.com

# A few problems with compiling Java from source:
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#       really hairy.

# Default to UTF-8 file.encoding
ENV LANG=C.UTF-8

RUN apt-get update \
	&& apt-get install --no-install-recommends -y \
		dirmngr \
		gnupg \
	&& (echo "deb http://ppa.launchpad.net/openjdk-r/ppa/ubuntu xenial main" > /etc/apt/sources.list.d/openjdk-r-ubuntu-ppa-xenial.list) \
	&& apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EB9B1D8886F44E2A \
	&& apt-get update \
	&& apt-get install --no-install-recommends -y \
		openjdk-7-jre-headless \
		unzip \
	&& apt-get clean \
	&& rm -f /var/lib/apt/lists/*_dists_*

# If you're reading this and have any feedback on how this image could be
#   improved, please open an issue or a pull request so we can discuss it!
