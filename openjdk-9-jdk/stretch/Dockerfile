FROM buildpack-deps:stretch-scm

MAINTAINER vicamo@gmail.com

# A few problems with compiling Java from source:
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#       really hairy.

# Default to UTF-8 file.encoding
ENV LANG=C.UTF-8

RUN set -x \
	&& echo 'deb http://httpredir.debian.org/debian stretch-backports main' > /etc/apt/sources.list.d/stretch-backports.list \
	&& apt-get update \
	&& apt-get install --no-install-recommends -y \
		ca-certificates-java \
		openjdk-9-jdk \
		unzip \
	&& /var/lib/dpkg/info/ca-certificates-java.postinst configure \
	&& apt-get clean \
	&& rm -f /var/lib/apt/lists/*_dists_*

# If you're reading this and have any feedback on how this image could be
#   improved, please open an issue or a pull request so we can discuss it!
