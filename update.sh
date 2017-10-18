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
	[openjdk-8-jessie]='jessie-backports'
	[openjdk-9-stretch]='stretch-backports'
)

declare -A variants=(
	[jre]='curl'
	[jdk]='scm'
)

alpineVersion='3.3'
alpineMirror="http://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/community/x86_64"
curl -fsSL'#' "$alpineMirror/APKINDEX.tar.gz" | tar -zxv APKINDEX

travisEnv=
for version in "${versions[@]}"; do
	java="${version%%/*}" # "openjdk-6-jdk"
	flavor="${java%%-*}" # "openjdk"
	javaVersion="${java#*-}" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-*}" # "6"

	suite="${version##*/}"
	addSuite="${addSuites[$flavor-$javaVersion-$suite]}"
	variant="${variants[$javaType]}"

	needCaHack=
	if [ "$flavor" = 'openjdk' ]; then
		if [ "$javaVersion" -ge 8 ]; then
			needCaHack=1
		fi
	fi

	dist="${doru[$suite]}:${addSuite:-$suite}"
	if [ "$flavor" = 'java' ]; then
		debianPackage=oracle-java$javaVersion-installer
	else
		debianPackage="$flavor-$javaVersion-$javaType"
		if [ "$javaType" = 'jre' ]; then
			debianPackage+='-headless'
		fi
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
	&& (echo 'deb http://httpredir.debian.org/debian $addSuite main' > /etc/apt/sources.list.d/$addSuite.list) \\
EOD
	fi

	cat >> "$version/Dockerfile" <<EOD
	&& apt-get update \\
	&& apt-get install --no-install-recommends -y \\
EOD

	if [ "$flavor" = 'java' ]; then
		cat >> "$version/Dockerfile" <<EOD
		dirmngr \\
		gnupg \\
		unzip \\
	&& (echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu ${oracleJavaSuite[$suite]} main" > /etc/apt/sources.list.d/webupd8team-ubuntu-java.list) \\
	&& apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C2518248EEA14886 \\
	&& (echo "debconf shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections) \\
	&& (echo "debconf shared/accepted-oracle-license-v1-1 seen true" | debconf-set-selections) \\
	&& apt-get update \\
	&& apt-get install --no-install-recommends -y \\
		$debianPackage \\
	&& rm -rf /var/cache/oracle-jdk$javaVersion-installer \\
EOD
	else
		cat >> "$version/Dockerfile" <<EOD
		$debianPackage \\
		unzip \\
EOD
		if [ "$needCaHack" ]; then
			cat >> "$version/Dockerfile" <<EOD
		ca-certificates-java="20140324" \\
	&& /var/lib/dpkg/info/ca-certificates-java.postinst configure \\
EOD
		fi
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
		EOD
		cat >> "$version/$variant/Dockerfile" <<-'EOD'
			ENV PATH $PATH:$JAVA_HOME/bin
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
