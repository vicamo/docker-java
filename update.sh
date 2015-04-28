#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

variants=( "$@" )
if [ ${#variants[@]} -eq 0 ]; then
	variants=$(ls -d -1 */*)
fi
variants=( "${variants[@]%/}" )


for variant in ${variants[@]}; do
	echo "### $variant ###"
	[ -d "$variant" ] || continue;
	echo -n "Checking $variant ... "

	version="${variant%%/*}"
	flavor="${version%%-*}" # "openjdk" or "java"
	javaVersion="${version#*-}" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-*}" # "6"
	
	dist="$(grep '^FROM ' "$variant/Dockerfile" | cut -d' ' -f2)"
	
	fullVersion=
	case "$flavor" in
		openjdk)
			debianVersion="$(set -x; docker run --rm "$dist" bash -c "apt-get update &> /dev/null && apt-cache show $flavor-$javaVersion-$javaType | grep '^Version: ' | head -1 | cut -d' ' -f2")"
			;;
		java)
			debianVersion="$(set -x; docker run --rm "$dist" bash -c "echo 'deb http://ppa.launchpad.net/webupd8team/java/ubuntu devel main' > /etc/apt/sources.list.d/webupd8team-ubuntu-java.list && apt-get update &> /dev/null && apt-cache show oracle-java$javaVersion-installer | grep '^Version: ' | head -1 | cut -d' ' -f2")"
			;;
	esac
	
	if [ "$debianVersion" ]; then
		fullVersion="${debianVersion%%-*}"
		fullVersion="${fullVersion%%+*}"
		(
			set -x
			sed -ri '
				s/(\<JAVA_VERSION)=[^ ]+/\1='"$fullVersion"'/g;
				s/(\<JAVA_DEBIAN_VERSION)=[^ ]+/\1='"$debianVersion"'/g;
			' "$variant/Dockerfile"
		)
	fi
done

