.PHONY: all lint format check typecheck

all: typecheck lint format

lint:
	luacheck .

format:
	stylua --glob '!ignored/**' --glob '*.lua' .

typecheck:
	lua-language-server --check . --checklevel=Warning

check: typecheck lint
	stylua --check --glob '!ignored/**' --glob '*.lua' .
