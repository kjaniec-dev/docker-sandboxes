.PHONY: test verify rebuild rebuild-claude rebuild-codex

test:
	./tests/run.sh

verify:
	./harnesses/claude-code/scripts/verify.sh

rebuild:
	$(MAKE) rebuild-claude

rebuild-claude:
	./bin/claude-sbx-rebuild

rebuild-codex:
	./bin/codex-sbx-rebuild
