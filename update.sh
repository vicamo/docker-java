#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */*/ )
fi
versions=( "${versions[@]%/}" )

declare -A doru=(
	[artful]='ubuntu'
	[buster]='debian'
	[jessie]='debian'
	[sid]='debian'
	[stretch]='debian'
	[trusty]='ubuntu'
	[wheezy]='debian'
	[xenial]='ubuntu'
	[zesty]='ubuntu'
)

declare -A oracleJavaSuite=(
	[artful]='artful'
	[buster]='vivid'
	[jessie]='vivid'
	[sid]='vivid'
	[stretch]='vivid'
	[trusty]='trusty'
	[wheezy]='vivid'
	[xenial]='xenial'
	[zesty]='zesty'
)

declare -A addSuites=(
	[8-jessie]='jessie-backports'
	[9-stretch]='stretch-backports'
)

declare -A variants=(
	[jre]='curl'
	[jdk]='scm'
)

alpineVersion='3.5'
alpineMirror="http://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/community/x86_64"
curl -fsSL'#' "$alpineMirror/APKINDEX.tar.gz" | tar -zxv APKINDEX

travisEnv=
for version in "${versions[@]}"; do
	javaVersion="${version%%/*}" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-*}" # "6"

	suite="${version##*/}"
	addSuite="${addSuites[$javaVersion-$suite]}"
	variant="${variants[$javaType]}"

	needCaHack=
	if [ "$javaVersion" -ge 8 -a "$suite" != 'sid' ]; then
		# "20140324" is broken (jessie), but "20160321" is fixed (sid)
		needCaHack=1
	fi

	dist="${doru[$suite]}:${addSuite:-$suite}"
	debianPackage="openjdk-$javaVersion-$javaType"
	if [ "$javaType" = 'jre' -o "$javaVersion" -ge 9 ]; then
		# "openjdk-9" in Debian introduced an "openjdk-9-jdk-headless" package \o/
		debianPackage+='-headless'
	fi

	cat > "$version/Dockerfile" <<-EOD
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

		FROM buildpack-deps:$suite-$variant

		# A few problems with compiling Java from source:
		#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
		#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
		#       really hairy.

	EOD

	cat >> "$version/Dockerfile" <<-EOD
		# Default to UTF-8 file.encoding
		ENV LANG C.UTF-8

	EOD

	cat >> "$version/Dockerfile" <<-EOD
		RUN set -x \\
	EOD

	if [ "$addSuite" ]; then
		cat >> "$version/Dockerfile" <<EOD
	&& (echo 'deb http://deb.debian.org/debian $addSuite main' > /etc/apt/sources.list.d/$addSuite.list) \\
EOD
	fi

	cat >> "$version/Dockerfile" <<EOD
	&& apt-get update \\
	&& apt-get install --no-install-recommends -y \\
EOD

	cat >> "$version/Dockerfile" <<EOD
		bzip2 \\
		$debianPackage \\
		unzip \\
		xz-utils \\
EOD
	if [ "$needCaHack" ]; then
			cat >> "$version/Dockerfile" <<EOD
		ca-certificates-java="20140324" \\
	&& /var/lib/dpkg/info/ca-certificates-java.postinst configure \\
EOD
	fi
	cat >> "$version/Dockerfile" <<EOD
	&& apt-get clean \\
	&& rm -rf /var/lib/apt/lists/*_dists_*

EOD

	cat >> "$version/Dockerfile" <<-EOD
		# If you're reading this and have any feedback on how this image could be
		#   improved, please open an issue or a pull request so we can discuss it!
	EOD

	variant='alpine'
	if [ -d "$version/$variant" ]; then
		alpinePackage="openjdk$javaVersion"
		alpineJavaHome="/usr/lib/jvm/java-1.${javaVersion}-openjdk"
		alpinePathAdd="$alpineJavaHome/jre/bin:$alpineJavaHome/bin"
		case "$javaType" in
			jdk)
				;;
			jre)
				alpinePackage+="-$javaType"
				alpineJavaHome+="/$javaType"
				;;
		esac
		alpinePackageVersion="$(awk -F: '$1 == "P" { pkg = $2 } pkg == "'"$alpinePackage"'" && $1 == "V" { print $2 }' APKINDEX)"
		alpineFullVersion="${alpinePackageVersion/./u}"
		alpineFullVersion="${alpineFullVersion%%.*}"

		cat > "$version/$variant/Dockerfile" <<-EOD
			#
			# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
			#
			# PLEASE DO NOT EDIT IT DIRECTLY.
			#

			FROM alpine:$alpineVersion

			# A few problems with compiling Java from source:
			#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
			#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
			#       really hairy.

			# Default to UTF-8 file.encoding
			ENV LANG C.UTF-8
		EOD

		cat >> "$version/$variant/Dockerfile" <<-EOD
			ENV JAVA_HOME $alpineJavaHome
			ENV PATH \$PATH:$alpinePathAdd
		EOD
		cat >> "$version/$variant/Dockerfile" <<-EOD

			ENV JAVA_VERSION $alpineFullVersion
			ENV JAVA_ALPINE_VERSION $alpinePackageVersion
		EOD
		cat >> "$version/$variant/Dockerfile" <<EOD

RUN set -x \\
	&& apk add --no-cache \\
		${alpinePackage}="\$JAVA_ALPINE_VERSION"
EOD

		travisEnv='\n  - VERSION='"$version"' VARIANT='"$variant$travisEnv"
	fi

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '($1 == "env:") { $0 = substr($0, 0, index($0, "matrix:") + length("matrix:") - 1)"'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

rm APKINDEX
