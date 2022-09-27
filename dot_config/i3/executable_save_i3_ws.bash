#!/bin/bash
WORKSPACE_NUM=$1
WORKSPACE_PATH=~/.config/i3/workspaces/workspace_$WORKSPACE_NUM.json

test_ws_num() {
	if [[ $1 -lt 1 || $1 -gt 6 ]]; then
		echo "Usage: ./script.sh <ws_num> [save|test [<restore_ws_num>]]"
		exit 1
	fi
}

test_ws_num $WORKSPACE_NUM

if [[ -z $2 || $2 == "save" ]]; then
	i3-save-tree --workspace $WORKSPACE_NUM > $WORKSPACE_PATH
	sed --in-place --regexp-extended \
		--expression='s|^(\s*)// "|\1"|g; /^\s*\/\//d' \
		--expression="/\"machine\":/d" \
		--expression="s/(\"name\": \"\[.*\]).*$/\1\",/" \
		--expression="s/(\"title\": \".*\[.*\]).*$/\1\",/" \
		--expression="s/(\"name\": \"Telegram).*$/\1\",/" \
		--expression="s/(\"title\": \"\^Telegram).*\"(,*)$/\1\"\2/" \
		$WORKSPACE_PATH
	echo "Succesfully saved workspace \`$WORKSPACE_NUM\` to \`$WORKSPACE_PATH\`"
	echo "You may want to check and fix it a bit"
fi

if [[ $2 == "test" ]]; then
	if [[ -n $3 ]]; then
		test_ws_num $3
		WORKSPACE_NUM=$3
	fi
	echo "Succesfully restored workspace \`$WORKSPACE_NUM\` from \`$WORKSPACE_PATH\`"
	i3-msg "workspace $WORKSPACE_NUM; append_layout $WORKSPACE_PATH"
fi
