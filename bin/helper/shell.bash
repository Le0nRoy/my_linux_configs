#!/bin/bash
# Helper Shell Module - portable interactive conveniences
# Public helpers only; loaded by interactive Bash (helper.bash) on Linux and
# macOS. Zsh runs these unchanged bodies through Bash (bash_exec.zsh).
# No dependencies

# hh_colors - print the terminal's ANSI color table
hh_colors() {
	local fgc bgc vals seq0

	printf "Color escapes are %s\n" '\e[${value};...;${value}m'
	printf "Values 30..37 are \e[33mforeground colors\e[m\n"
	printf "Values 40..47 are \e[43mbackground colors\e[m\n"
	printf "Value  1 gives a  \e[1mbold-faced look\e[m\n\n"

	# foreground colors
	for fgc in {30..37}; do
		# background colors
		for bgc in {40..47}; do
			fgc=${fgc#37} # white
			bgc=${bgc#40} # black

			vals="${fgc:+$fgc;}${bgc}"
			vals=${vals%%;}

			seq0="${vals:+\e[${vals}m}"
			printf "  %-9s" "${seq0:-(default)}"
			printf " ${seq0}TEXT\e[m"
			printf " \e[${vals:+${vals+$vals;}}1mBOLD\e[m"
		done
		echo; echo
	done
}

# hh_unar - archive extractor
# usage: hh_unar <archive>
# Extracts into the current directory. Errors go to stderr; the status is
# non-zero for a usage error, a missing file, an unsupported type or a
# failed extraction (the extractor's own status).
hh_unar() {
	if (($# != 1)); then
		echo "Usage: hh_unar <archive>" >&2
		return 1
	fi
	local file="$1"
	if [[ ! -e "${file}" ]]; then
		echo "hh_unar: '${file}': no such file" >&2
		return 1
	fi
	if [[ ! -f "${file}" ]]; then
		echo "hh_unar: '${file}': not a regular file" >&2
		return 1
	fi
	case "${file}" in
		*.tar.bz2|*.tbz2) tar xjf "${file}" ;;
		*.tar.gz|*.tgz)   tar xzf "${file}" ;;
		*.tar)            tar xf "${file}" ;;
		*.bz2)            bunzip2 "${file}" ;;
		*.rar)            unrar x "${file}" ;;
		*.gz)             gunzip "${file}" ;;
		*.zip)            unzip "${file}" ;;
		*.Z)              uncompress "${file}" ;;
		*.7z)             7z x "${file}" ;;
		*)
			echo "hh_unar: '${file}': unsupported archive type" >&2
			return 1
			;;
	esac
}
