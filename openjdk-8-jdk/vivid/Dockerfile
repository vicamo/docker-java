FROM vicamo/buildpack-deps:vivid-scm

# A few problems with compiling Java from source:
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#       really hairy.

# Default to UTF-8 file.encoding
#
# For CA_CERTIFICATES_JAVA_VERSION, see https://bugs.debian.org/775775
# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
ENV LANG=C.UTF-8 \
	JAVA_VERSION=8u40 \
	JAVA_DEBIAN_VERSION=8u40-b27-1 \
	CA_CERTIFICATES_JAVA_VERSION=20140324

RUN apt-get update \
	&& apt-get install --no-install-recommends -y --force-yes \
		ca-certificates-java="$CA_CERTIFICATES_JAVA_VERSION" \
		openjdk-8-jdk="$JAVA_DEBIAN_VERSION" \
		unzip \
	&& /var/lib/dpkg/info/ca-certificates-java.postinst configure \
	&& apt-get clean \
	&& rm -f /var/lib/apt/lists/*_dists_*

# If you're reading this and have any feedback on how this image could be
#   improved, please open an issue or a pull request so we can discuss it!
