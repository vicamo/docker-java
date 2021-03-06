#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */*/ )
fi
versions=( "${versions[@]%/}" )

# sort version numbers with lowest first
IFS=$'\n'; versions=( $(echo "${versions[*]}" | sort -V) ); unset IFS

declare -A doru=(
	[artful]='ubuntu'
	[bionic]='ubuntu'
	[buster]='debian'
	[cosmic]='ubuntu'
	[jessie]='debian'
	[sid]='debian'
	[stretch]='debian'
	[trusty]='ubuntu'
	[wheezy]='debian'
	[xenial]='ubuntu'
)

defaultAlpineVersion='3.8'
declare -A alpineVersions=(
	#[8]='3.7'
	#[10]='TBD' # there is no openjdk10 in Alpine yet (https://pkgs.alpinelinux.org/packages?name=openjdk*-jre&arch=x86_64)
)

declare -A addSuites=(
	[8-jessie]='jessie-backports'
	[9-stretch]='stretch-backports'
)

declare -A needBackportPpaSuites=(
	[7-xenial]='yes'
	[8-trusty]='yes'
)

declare -A buildpackDepsVariants=(
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
		for version in ${versions[@]+"${versions[@]}"}; do
			if [ -z "$latestVersion" ] || dpkg --compare-versions "$version" '>>' "$latestVersion"; then
				latestVersion="$version"
			fi
		done
	done

	debVerCache[$debVerCacheKey]="$latestVersion"
	echo "$latestVersion"
}

template-generated-warning() {
	local from="$1"; shift
	local javaVersion="$1"; shift

	cat <<-EOD
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

		FROM $from

		# A few reasons for installing distribution-provided OpenJDK:
		#
		#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
		#
		#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
		#     really hairy.
		#
		#     For some sample build times, see Debian's buildd logs:
		#       https://buildd.debian.org/status/logs.php?pkg=openjdk-$javaVersion
	EOD
}

template-java-home-script() {
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

template-contribute-footer() {
	cat <<-'EOD'

		# If you're reading this and have any feedback on how this image could be
		# improved, please open an issue or a pull request so we can discuss it!
		#
		#   https://github.com/docker-library/openjdk/issues
	EOD
}

travisEnv=
appveyorEnv=
for version in "${versions[@]}"; do
	javaVersion="${version#*/}"
	suite="${version%/*}"
	for javaType in jdk jre; do
		dir="$suite/$javaVersion/$javaType"

		addSuite="${addSuites[$javaVersion-$suite]:-}"
		needBackportPpa="${needBackportPpaSuites[$javaVersion-$suite]:-}"
		buildpackDepsVariant="${buildpackDepsVariants[$javaType]}"

		needCaHack=
		if [ "$javaVersion" -ge 8 -a "$suite" = 'jessie' ]; then
			# "20140324" is broken (jessie), but "20160321" is fixed (sid)
			needCaHack=1
		fi

		debianPackage="openjdk-$javaVersion-$javaType"
		debSuite="${addSuite:-$suite}"
		debian-latest-version "$debianPackage" "${doru[$suite]}" "$debSuite" > /dev/null # prime the cache

		template-generated-warning "buildpack-deps:$suite-$buildpackDepsVariant" "$javaVersion" > "$dir/Dockerfile"

		cat >> "$dir/Dockerfile" <<'EOD'

RUN apt-get update && apt-get install -y --no-install-recommends \
		bzip2 \
		unzip \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*
EOD

		if [ "$addSuite" ]; then
			cat >> "$dir/Dockerfile" <<-EOD

				RUN echo 'deb http://deb.debian.org/debian $addSuite main' > /etc/apt/sources.list.d/$addSuite.list
			EOD
		fi

		cat >> "$dir/Dockerfile" <<-EOD

			# Default to UTF-8 file.encoding
			ENV LANG C.UTF-8
		EOD

		template-java-home-script >> "$dir/Dockerfile"

		jreSuffix=
		if [ "$javaType" = 'jre' -a "$javaVersion" -lt 9 ]; then
			# woot, this hackery stopped in OpenJDK 9+!
			jreSuffix='/jre'
		fi
		cat >> "$dir/Dockerfile" <<-EOD

			# do some fancy footwork to create a JAVA_HOME that's cross-architecture-safe
			RUN ln -svT "/usr/lib/jvm/java-$javaVersion-openjdk-\$(dpkg --print-architecture)" /docker-java-home
			ENV JAVA_HOME /docker-java-home$jreSuffix
		EOD

		if [ "$needCaHack" ]; then
			debian-latest-version 'ca-certificates-java' "${doru[$suite]}" "$debSuite" > /dev/null # prime the cache
			caCertHackVersion="$(debian-latest-version 'ca-certificates-java' "${doru[$suite]}" "$debSuite")"
			cat >> "$dir/Dockerfile" <<-EOD

				# see https://bugs.debian.org/775775
				# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
				ENV CA_CERTIFICATES_JAVA_VERSION $caCertHackVersion
			EOD
		fi

		cat >> "$dir/Dockerfile" <<EOD

RUN set -ex; \\
	\\
# deal with slim variants not having man page directories (which causes "update-alternatives" to fail)
	if [ ! -d /usr/share/man/man1 ]; then \\
		mkdir -p /usr/share/man/man1; \\
	fi; \\
	\\
EOD

		if [ -n "$needBackportPpa" ]; then
			cat >> "$dir/Dockerfile" <<EOD
	echo "deb http://ppa.launchpad.net/openjdk-r/ppa/ubuntu $suite main" > /etc/apt/sources.list.d/openjdk-r-ubuntu-ppa-$suite.list; \\
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EB9B1D8886F44E2A; \\
EOD
		fi

		cat >> "$dir/Dockerfile" <<EOD
	apt-get update; \\
	apt-get install -y --no-install-recommends \\
		$debianPackage \\
EOD
		if [ "$needCaHack" ]; then
			# ca-certificates-java depends on jre, and apt may decide to install both. Explicitly exclude older one.
			cat >> "$dir/Dockerfile" <<EOD
		openjdk-$((javaVersion-1))-jre-headless- \\
		ca-certificates-java="\$CA_CERTIFICATES_JAVA_VERSION" \\
EOD
		fi
		cat >> "$dir/Dockerfile" <<EOD
	; \\
	rm -rf /var/lib/apt/lists/*; \\
	\\
# verify that "docker-java-home" returns what we expect
	[ "\$(readlink -f "\$JAVA_HOME")" = "\$(docker-java-home)" ]; \\
	\\
# update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
	update-alternatives --get-selections | awk -v home="\$(readlink -f "\$JAVA_HOME")" 'index(\$3, home) == 1 { \$2 = "manual"; print | "update-alternatives --set-selections" }'; \\
# ... and verify that it actually worked for one of the alternatives we care about
	update-alternatives --query java | grep -q 'Status: manual'
EOD

		if [ "$needCaHack" ]; then
			cat >> "$dir/Dockerfile" <<-EOD

				# see CA_CERTIFICATES_JAVA_VERSION notes above
				RUN /var/lib/dpkg/info/ca-certificates-java.postinst configure
			EOD
		fi

		if [ "$javaType" = 'jdk' ] && [ "$javaVersion" -ge 9 ]; then
			cat >> "$dir/Dockerfile" <<-'EOD'

				# https://docs.oracle.com/javase/9/tools/jshell.htm
				# https://en.wikipedia.org/wiki/JShell
				CMD ["jshell"]
			EOD
		fi

		template-contribute-footer >> "$dir/Dockerfile"

		if [ -d "$dir/alpine" ]; then
			alpineVersion="${alpineVersions[$javaVersion]:-$defaultAlpineVersion}"
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

			echo "$javaVersion-$javaType: $alpineFullVersion (alpine $alpinePackageVersion)"

			template-generated-warning "alpine:$alpineVersion" "$javaVersion" > "$dir/alpine/Dockerfile"

			cat >> "$dir/alpine/Dockerfile" <<-'EOD'

				# Default to UTF-8 file.encoding
				ENV LANG C.UTF-8
			EOD

			template-java-home-script >> "$dir/alpine/Dockerfile"

			cat >> "$dir/alpine/Dockerfile" <<-EOD
				ENV JAVA_HOME $alpineJavaHome
				ENV PATH \$PATH:$alpinePathAdd
			EOD
			cat >> "$dir/alpine/Dockerfile" <<-EOD

				ENV JAVA_VERSION $alpineFullVersion
				ENV JAVA_ALPINE_VERSION $alpinePackageVersion
			EOD
			cat >> "$dir/alpine/Dockerfile" <<EOD

RUN set -x \\
	&& apk add --no-cache \\
		${alpinePackage}="\$JAVA_ALPINE_VERSION" \\
	&& [ "\$JAVA_HOME" = "\$(docker-java-home)" ]
EOD

			template-contribute-footer >> "$dir/alpine/Dockerfile"
		fi

		if [ -d "$dir/slim" ]; then
			# for the "slim" variants,
			#   - swap "buildpack-deps:SUITE-xxx" for "debian:SUITE-slim"
			#   - swap "openjdk-N-(jre|jdk) for the -headless versions, where available (openjdk-8+ only for JDK variants)
			sed -r \
				-e 's!^FROM buildpack-deps:([^-]+)(-.+)?!FROM debian:\1-slim!' \
				-e 's!(openjdk-([0-9]+-jre|([89][0-9]*|[0-9][0-9]+)-jdk))=!\1-headless=!g' \
				"$dir/Dockerfile" > "$dir/slim/Dockerfile"
		fi

		if [ -d "$dir/windows" ]; then
			ojdkbuildVersion="$(
				git ls-remote --tags 'https://github.com/ojdkbuild/ojdkbuild' \
					| cut -d/ -f3 \
					| grep -E '^(1[.])?'"$javaVersion"'[.-]' \
					| sort -V \
					| tail -1
			)"
			if [ -z "$ojdkbuildVersion" ]; then
				echo >&2 "error: '$dir/windows' exists, but Java $javaVersion doesn't appear to have a corresponding ojdkbuild release"
				exit 1
			fi
			ojdkbuildZip="$(
				curl -fsSL "https://github.com/ojdkbuild/ojdkbuild/releases/tag/$ojdkbuildVersion" \
					| grep --only-matching -E 'java-[0-9.]+-openjdk-[b0-9.-]+[.]ojdkbuild(ea)?[.]windows[.]x86_64[.]zip' \
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

			if [[ "$ojdkbuildVersion" == *-ea-* ]]; then
				# convert "9-ea-b154-1" into "9-b154"
				ojdkJavaVersion="$(echo "$ojdkbuildVersion" | sed -r 's/-ea-/-/' | cut -d- -f1,2)"
			elif [[ "$ojdkbuildVersion" == 1.* ]]; then
				# convert "1.8.0.111-3" into "8u111"
				ojdkJavaVersion="$(echo "$ojdkbuildVersion" | cut -d. -f2,4 | cut -d- -f1 | tr . u)"
			elif [[ "$ojdkbuildVersion" == 10.* ]]; then
				# convert "10.0.1-1.b10" into "10.0.1"
				ojdkJavaVersion="${ojdkbuildVersion%%-*}"
			else
				echo >&2 "error: unable to parse ojdkbuild version $ojdkbuildVersion"
				exit 1
			fi

			echo "$javaVersion-$javaType: $ojdkJavaVersion (windows ojdkbuild $ojdkbuildVersion)"

			sed -ri \
				-e 's/^(ENV JAVA_VERSION) .*/\1 '"$ojdkJavaVersion"'/' \
				-e 's/^(ENV JAVA_OJDKBUILD_VERSION) .*/\1 '"$ojdkbuildVersion"'/' \
				-e 's/^(ENV JAVA_OJDKBUILD_ZIP) .*/\1 '"$ojdkbuildZip"'/' \
				-e 's/^(ENV JAVA_OJDKBUILD_SHA256) .*/\1 '"$ojdkbuildSha256"'/' \
				"$dir"/windows/*/Dockerfile

			for winVariant in \
				nanoserver-{1709,sac2016} \
				windowsservercore-{1709,ltsc2016} \
			; do
				[ -f "$dir/windows/$winVariant/Dockerfile" ] || continue

				sed -ri \
					-e 's!^FROM .*!FROM microsoft/'"${winVariant%%-*}"':'"${winVariant#*-}"'!' \
					"$dir/windows/$winVariant/Dockerfile"

				case "$winVariant" in
					*-1709) ;; # no AppVeyor support for 1709 yet: https://github.com/appveyor/ci/issues/1885
					*) appveyorEnv='\n    - version: '"$javaVersion"'\n      variant: '"$winVariant$appveyorEnv" ;;
				esac
			done
		fi
	done

	if [ -d "$version/jdk/alpine" ]; then
		travisEnv='\n  - SUITE='"$suite"' VERSION='"$javaVersion"' VARIANT=alpine'"$travisEnv"
	fi
	if [ -d "$version/jdk/slim" ]; then
		travisEnv='\n  - SUITE='"$suite"' VERSION='"$javaVersion"' VARIANT=slim'"$travisEnv"
	fi
	travisEnv='\n  - SUITE='"$suite"' VERSION='"$javaVersion$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '($1 == "env:") { $0 = substr($0, 0, index($0, "matrix:") + length("matrix:") - 1)"'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

appveyor="$(awk -v 'RS=\n\n' '$1 == "environment:" { $0 = "environment:\n  matrix:'"$appveyorEnv"'" } { printf "%s%s", $0, RS }' .appveyor.yml)"
echo "$appveyor" > .appveyor.yml
