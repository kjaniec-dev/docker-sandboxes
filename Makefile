.PHONY: test verify verify-browser verify-opencode verify-agy verify-junie rebuild rebuild-claude rebuild-codex rebuild-opencode rebuild-agy rebuild-junie

test:
	./tests/run.sh

verify:
	./harnesses/claude-code/scripts/verify.sh

verify-browser:
	bash shared/verify-browser.sh

verify-opencode:
	./harnesses/opencode/scripts/verify.sh

verify-agy:
	./harnesses/antigravity-cli/scripts/verify.sh

verify-junie:
	./harnesses/junie/scripts/verify.sh

rebuild:
	$(MAKE) rebuild-claude rebuild-codex rebuild-opencode rebuild-agy rebuild-junie

rebuild-claude:
	./bin/claude-sbx-rebuild

rebuild-codex:
	./bin/codex-sbx-rebuild

rebuild-opencode:
	./bin/opencode-sbx-rebuild

rebuild-agy:
	./bin/agy-sbx-rebuild

rebuild-junie:
	./bin/junie-sbx-rebuild
