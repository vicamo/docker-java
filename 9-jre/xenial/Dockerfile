#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM buildpack-deps:xenial-curl

# A few problems with compiling Java from source:
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#       really hairy.

# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

# see https://bugs.debian.org/775775
# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
ENV CA_CERTIFICATES_JAVA_VERSION 20160321

RUN set -x \
	&& apt-get update \
	&& apt-get install --no-install-recommends -y \
		bzip2 \
		openjdk-9-jre-headless \
		unzip \
		xz-utils \
		ca-certificates-java="$CA_CERTIFICATES_JAVA_VERSION" \
	&& /var/lib/dpkg/info/ca-certificates-java.postinst configure \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*_dists_*

# If you're reading this and have any feedback on how this image could be
#   improved, please open an issue or a pull request so we can discuss it!
