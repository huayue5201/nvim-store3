.PHONY: test lint check docs

test:
	./scripts/test.sh $(filter-out $@,$(MAKECMDGOALS))

lint:
	luacheck lua plugin test

check: lint test

docs:
	nvim --headless -u NONE -c 'set rtp+=$(CURDIR)' -c 'helptags doc' -c q

%:
	@:
