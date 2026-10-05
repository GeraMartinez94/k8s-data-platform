SHELL := /bin/bash
.PHONY: preflight up down test
# export TF_VAR_localstack_auth_token=<free token> before `make up`
# (not needed with a no-token emulator: export TF_VAR_emulator_image=<image>)

IMAGE := $(or $(TF_VAR_emulator_image),localstack/localstack:latest)

preflight:
	@fail=0; \
	for t in docker kind kubectl terraform; do \
		command -v $$t >/dev/null || { echo "ERROR: '$$t' is not installed"; fail=1; }; \
	done; \
	if command -v docker >/dev/null && ! docker info >/dev/null 2>&1; then \
		echo "ERROR: Docker is installed but not running"; fail=1; fi; \
	if [[ "$(IMAGE)" == *localstack* && -z "$$TF_VAR_localstack_auth_token" ]]; then \
		echo "ERROR: LocalStack needs a token: export TF_VAR_localstack_auth_token=... (or set TF_VAR_emulator_image to a no-token emulator)"; fail=1; fi; \
	if (echo > /dev/tcp/127.0.0.1/4566) 2>/dev/null; then \
		echo "ERROR: port 4566 is already in use"; fail=1; fi; \
	if kind get clusters 2>/dev/null | grep -qx data-platform; then \
		echo "ERROR: cluster 'data-platform' already exists (run: make down)"; fail=1; fi; \
	[[ $$fail -eq 0 ]] && echo "preflight OK"; exit $$fail

up: preflight
	kind create cluster --name data-platform
	docker build -t data-api:dev app
	kind load docker-image data-api:dev --name data-platform
	cd infra/cluster && terraform init && terraform apply -auto-approve
	kubectl -n data rollout status deploy/aws-emulator --timeout=180s
	kubectl -n data port-forward svc/aws-emulator 4566:4566 >/dev/null 2>&1 & echo $$! > .pf.pid
	for i in $$(seq 1 20); do (echo > /dev/tcp/127.0.0.1/4566) 2>/dev/null && break; sleep 1; done
	cd infra/aws && terraform init && terraform apply -auto-approve
	kubectl -n data rollout restart deploy/data-api

test:
	kubectl -n data port-forward svc/data-api 8000:80 >/dev/null 2>&1 & echo $$! > .pf2.pid
	sleep 3
	curl -s -X PUT localhost:8000/objects/hello -H 'content-type: application/json' -d '{"msg":"hola"}'
	curl -s localhost:8000/objects
	-kill `cat .pf2.pid`

down:
	-kill `cat .pf.pid`
	kind delete cluster --name data-platform
	rm -rf .pf.pid .pf2.pid infra/*/terraform.tfstate*
