.PHONY: lint syntax demo clean

lint:
	yamllint .
	ansible-lint

syntax:
	cd ansible && ansible-playbook deploy.yml --syntax-check
	cd ansible && ansible-playbook deploy_naive.yml --syntax-check

demo:
	scripts/demo.sh

clean:
	scripts/demo.sh clean
