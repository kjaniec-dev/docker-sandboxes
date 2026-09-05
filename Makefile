.PHONY: test verify verify-opencode rebuild rebuild-claude rebuild-codex rebuild-opencode

test:
	./tests/run.sh

verify:
	./harnesses/claude-code/scripts/verify.sh

verify-opencode:
	./harnesses/opencode/scripts/verify.sh

rebuild:
	$(MAKE) rebuild-claude

rebuild-claude:
	./bin/claude-sbx-rebuild

rebuild-codex:
	./bin/codex-sbx-rebuild

rebuild-opencode:
	./bin/opencode-sbx-rebuild
