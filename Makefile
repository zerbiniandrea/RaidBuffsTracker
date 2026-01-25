.PHONY: all lint format check typecheck

all: typecheck lint format

lint:
	luacheck .

format:
	stylua .

typecheck:
	lua-language-server --check . --checklevel=Warning

check: typecheck lint
	stylua --check .
