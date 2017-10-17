FROM buildpack-deps:buster-curl

MAINTAINER vicamo@gmail.com

# A few problems with compiling Java from source:
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#       really hairy.

# Default to UTF-8 file.encoding
ENV LANG=C.UTF-8

# For libfontconfig1, see https://bugs.debian.org/793210
# and https://github.com/docker-library/java/issues/46#issuecomment-119026586
RUN apt-get update \
	&& apt-get install --no-install-recommends -y \
		ca-certificates-java \
		libfontconfig1 \
		openjdk-9-jre-headless \
		unzip \
	&& /var/lib/dpkg/info/ca-certificates-java.postinst configure \
	&& apt-get clean \
	&& rm -f /var/lib/apt/lists/*_dists_*

# If you're reading this and have any feedback on how this image could be
#   improved, please open an issue or a pull request so we can discuss it!
