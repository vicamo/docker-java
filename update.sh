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
declare -A alpineVersions=(
	[7]='3.4'
	[8]='3.5'
	[9]='3.5'
)

declare -A addSuites=(
	[8-jessie]='jessie-backports'
	[9-stretch]='stretch-backports'
)

declare -A variants=(
	[jre]='curl'
	[jdk]='scm'
)

declare -A debCache=()
declare -A debVerCache=()
dpkgArch="$(dpkg --print-architecture)"
debian-latest-version() {
	local package="$1"; shift
	local dist="$1"; shift
	local suite="$1"; shift

	local debVerCacheKey="$package-$suite"
	if [ -n "${debVerCache[$debVerCacheKey]:-}" ]; then
		echo "${debVerCache[$debVerCacheKey]}"
		return
	fi

	local debMirror;
	local secMirror;
	case "$dist" in
		debian)
			debMirror='https://deb.debian.org/debian'
			secMirror='http://security.debian.org'
			;;
		ubuntu)
			debMirror='http://archive.ubuntu.com/ubuntu'
			secMirror='http://security.ubuntu.com/ubuntu'
			;;
	esac

	local remotes=( "$debMirror/dists/$suite/main" )
	case "$suite" in
		sid) ;;

		experimental)
			remotes+=( "$debMirror/dists/sid/main" )
			;;

		*-backports)
			suite="${suite%-backports}"
			remotes+=( "$debMirror/dists/$suite/main" )
			;&
		*)
			remotes+=(
				"$debMirror/dists/$suite-updates/main"
				"$secMirror/dists/$suite/updates/main"
			)
			;;
	esac

	local latestVersion= remote=
	for remote in "${remotes[@]}"; do
		if [ -z "${debCache[$remote]:-}" ]; then
			local urlBase="$remote/binary-$dpkgArch/Packages" url= decomp=
			for comp in xz bz2 gz ''; do
				if wget --quiet --spider "$urlBase.$comp"; then
					url="$urlBase.$comp"
					case "$comp" in
						xz) decomp='xz -d' ;;
						bz2) decomp='bunzip2' ;;
						gz) decomp='gunzip' ;;
						'') decomp='cat' ;;
					esac
					break
				fi
			done
			if [ -z "$url" ]; then
				continue
			fi
			debCache[$remote]="$(wget -qO- "$url" | eval "$decomp")"
		fi
		IFS=$'\n'
		local versions=( $(
			echo "${debCache[$remote]}" \
				| awk -F ': ' '
					$1 == "Package" { pkg = $2 }
					pkg == "'"$package"'" && $1 == "Version" { print $2 }
				'
		) )
		unset IFS
		local version=
		for version in "${versions[@]}"; do
			if [ -z "$latestVersion" ] || dpkg --compare-versions "$version" '>>' "$latestVersion"; then
				latestVersion="$version"
			fi
		done
	done

	debVerCache[$debVerCacheKey]="$latestVersion"
	echo "$latestVersion"
}

java-home-script() {
	cat <<'EOD'

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/sh'; \
		echo 'set -e'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home
EOD
}

travisEnv=
appveyorEnv=
for version in "${versions[@]}"; do
	javaVersion="${version%%/*}" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-*}" # "6"

	suite="${version##*/}"
	addSuite="${addSuites[$javaVersion-$suite]}"
	variant="${variants[$javaType]}"

	javaHome="/usr/lib/jvm/java-$javaVersion-openjdk-$dpkgArch"
	if [ "$javaType" = 'jre' -a "$javaVersion" -lt 9 ]; then
		# woot, this hackery stopped in OpenJDK 9+!
		javaHome+='/jre'
	fi

	needCaHack=
	if [ "$javaVersion" -ge 8 -a "$suite" != 'sid' ]; then
		# "20140324" is broken (jessie), but "20160321" is fixed (sid)
		needCaHack=1
	fi

	debianPackage="openjdk-$javaVersion-$javaType"
	if [ "$javaType" = 'jre' -o "$javaVersion" -ge 9 ]; then
		# "openjdk-9" in Debian introduced an "openjdk-9-jdk-headless" package \o/
		debianPackage+='-headless'
	fi
	dist="${doru[$suite]}:${addSuite:-$suite}"
	debSuite="${addSuite:-$suite}"

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

	java-home-script >> "$version/Dockerfile"

	cat >> "$version/Dockerfile" <<-EOD

		ENV JAVA_HOME $javaHome

	EOD

	if [ "$needCaHack" ]; then
		debian-latest-version 'ca-certificates-java' "${doru[$suite]}" "$debSuite" > /dev/null # prime the cache
		caCertHackVersion="$(debian-latest-version 'ca-certificates-java' "${doru[$suite]}" "$debSuite")"
		cat >> "$version/Dockerfile" <<-EOD
			# see https://bugs.debian.org/775775
			# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
			ENV CA_CERTIFICATES_JAVA_VERSION $caCertHackVersion

		EOD
	fi

	cat >> "$version/Dockerfile" <<EOD
RUN set -ex; \\
	\\
EOD

	if [ "$addSuite" ]; then
		cat >> "$version/Dockerfile" <<EOD
	(echo 'deb http://deb.debian.org/debian $addSuite main' > /etc/apt/sources.list.d/$addSuite.list) \\
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
		ca-certificates-java="\$CA_CERTIFICATES_JAVA_VERSION" \\
	&& /var/lib/dpkg/info/ca-certificates-java.postinst configure \\
EOD
	fi
	cat >> "$version/Dockerfile" <<EOD
	&& apt-get clean \\
	; \\
	rm -rf /var/lib/apt/lists/*_dists_*; \\
# verify that "docker-java-home" returns what we expect
	[ "\$JAVA_HOME" = "\$(docker-java-home)" ]; \\
	\\
# update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
	update-alternatives --get-selections | awk -v home="\$JAVA_HOME" 'index(\$3, home) == 1 { \$2 = "manual"; print | "update-alternatives --set-selections" }'; \\
# ... and verify that it actually worked for one of the alternatives we care about
	update-alternatives --query java | grep -q 'Status: manual'

EOD

	cat >> "$version/Dockerfile" <<-EOD
		# If you're reading this and have any feedback on how this image could be
		#   improved, please open an issue or a pull request so we can discuss it!
	EOD

	variant='alpine'
	if [ -d "$version/$variant" ]; then
		alpineVersion="${alpineVersions[$javaVersion]}"
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

		alpineMirror="http://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/community/x86_64"
		alpinePackageVersion="$(
			wget -qO- "$alpineMirror/APKINDEX.tar.gz" \
				| tar --extract --gzip --to-stdout APKINDEX \
				| awk -F: '$1 == "P" { pkg = $2 } pkg == "'"$alpinePackage"'" && $1 == "V" { print $2 }'
		)"

		alpineFullVersion="${alpinePackageVersion/./u}"
		alpineFullVersion="${alpineFullVersion%%.*}"

		echo "$version: $alpineFullVersion (alpine $alpinePackageVersion)"

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

	if [ -d "$version/windows" ]; then
		ojdkbuildVersion="$(
			git ls-remote --tags 'https://github.com/ojdkbuild/ojdkbuild' \
				| cut -d/ -f3 \
				| grep -E '^1[.]'"$javaVersion"'[.]' \
				| sort -V \
				| tail -1
		)"
		if [ -z "$ojdkbuildVersion" ]; then
			echo >&2 "error: '$version/windows' exists, but Java $javaVersion doesn't appear to have a corresponding ojdkbuild release"
			exit 1
		fi
		ojdkbuildZip="$(
			curl -fsSL "https://github.com/ojdkbuild/ojdkbuild/releases/tag/$ojdkbuildVersion" \
				| grep --only-matching -E 'java-'"$(echo "$ojdkbuildVersion" | cut -d. -f1-3)"'-openjdk-'"$ojdkbuildVersion"'[.][b0-9]+[.]ojdkbuild[.]windows[.]x86_64[.]zip' \
				| sort -u
		)"
		if [ -z "$ojdkbuildZip" ]; then
			echo >&2 "error: $ojdkbuildVersion doesn't appear to have the release file we need (yet?)"
			exit 1
		fi
		ojdkbuildSha256="$(curl -fsSL "https://github.com/ojdkbuild/ojdkbuild/releases/download/${ojdkbuildVersion}/${ojdkbuildZip}.sha256" | cut -d' ' -f1)"
		if [ -z "$ojdkbuildSha256" ]; then
			echo >&2 "error: $ojdkbuildVersion seems to have $ojdkbuildZip, but no sha256 for it"
			exit 1
		fi
		ojdkJavaVersion="$(echo "$ojdkbuildVersion" | cut -d. -f2,4 | cut -d- -f1 | tr . u)" # convert "1.8.0.111-3" into "8u111"

		echo "$version: $ojdkJavaVersion (windows ojdkbuild $ojdkbuildVersion)"

		sed -ri \
			-e 's/^(ENV JAVA_VERSION) .*/\1 '"$ojdkJavaVersion"'/' \
			-e 's/^(ENV JAVA_OJDKBUILD_VERSION) .*/\1 '"$ojdkbuildVersion"'/' \
			-e 's/^(ENV JAVA_OJDKBUILD_ZIP) .*/\1 '"$ojdkbuildZip"'/' \
			-e 's/^(ENV JAVA_OJDKBUILD_SHA256) .*/\1 '"$ojdkbuildSha256"'/' \
			"$version"/windows/*/Dockerfile

		for df in "$version"/windows/*/Dockerfile; do
			appveyorEnv='\n    - version: '"$version"'\n      variant: '"$(basename "$(dirname "$df")")$appveyorEnv"
		done
	fi

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '($1 == "env:") { $0 = substr($0, 0, index($0, "matrix:") + length("matrix:") - 1)"'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

appveyor="$(awk -v 'RS=\n\n' '$1 == "environment:" { $0 = "environment:\n  matrix:'"$appveyorEnv"'" } { printf "%s%s", $0, RS }' .appveyor.yml)"
echo "$appveyor" > .appveyor.yml
