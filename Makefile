.PHONY: all lint format check

all: lint format

lint:
	luacheck .

format:
	stylua .

check: lint
	stylua --check .
