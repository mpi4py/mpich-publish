build:
	./bootstrap.sh
	./build-wheel.sh dist
	./check-wheel.sh dist

lint:
	codespell *.sh */*.py
	shellcheck *.sh
	ruff -n package/*.py
	yamllint .github/

clean:
	$(RM) -r package/build
	$(RM) -r package/LICENSE
	$(RM) -r package/install
	$(RM) -r package/sources
	$(RM) -r package/workdir
	$(RM) -r package/*.egg-info
	$(RM) -r .*_cache
