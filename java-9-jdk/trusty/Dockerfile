FROM vicamo/buildpack-deps:trusty-scm

ENV JAVA_VERSION=9b55 \
	JAVA_DEBIAN_VERSION=9b55-1~webupd8~0

RUN echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu trusty main" > /etc/apt/sources.list.d/webupd8team-ubuntu-java.list \
	&& apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C2518248EEA14886 \
	&& echo "debconf shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections \
	&& echo "debconf shared/accepted-oracle-license-v1-1 seen true" | debconf-set-selections \
	&& apt-get update \
	&& apt-get install --no-install-recommends -y --force-yes \
		oracle-java9-installer="$JAVA_DEBIAN_VERSION" \
		unzip \
	&& apt-get clean \
	&& rm -rf /var/cache/oracle-jdk9-installer \
	&& rm -f /var/lib/apt/lists/*_dists_*
