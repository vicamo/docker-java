FROM buildpack-deps:jessie-scm

MAINTAINER vicamo@gmail.com

# Default to UTF-8 file.encoding
ENV LANG=C.UTF-8

RUN echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu vivid main" > /etc/apt/sources.list.d/webupd8team-ubuntu-java.list \
	&& apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C2518248EEA14886 \
	&& echo "debconf shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections \
	&& echo "debconf shared/accepted-oracle-license-v1-1 seen true" | debconf-set-selections \
	&& apt-get update \
	&& apt-get install --no-install-recommends -y \
		oracle-java7-installer \
		unzip \
	&& apt-get clean \
	&& rm -rf /var/cache/oracle-jdk7-installer \
	&& rm -f /var/lib/apt/lists/*_dists_*
