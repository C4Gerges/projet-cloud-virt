# Projet pour l'UE « Cloud et Virtualisation »

Sujet : [`./sujet/`](./sujet/README.md)

Backend / worker : [`./api/`](./api/README.md)

Frontend : [`./web/`](./web/README.md)

## Images Packer

Les images OpenStack sont construites avec [Packer](https://www.packer.io/).
Voir [`./packer/`](./packer/README.md) pour la documentation complète.

## Formatting

Markdown files are formatted with [Prettier](https://prettier.io/). A CI check
ensures all markdown files are properly formatted on PRs and pushes to main.

```sh
npm run format        # auto-fix all markdown files
npm run format:check  # check without modifying (used in CI)
```

## Connect to AWS

```
# aws configure sso
SSO session name (Recommended): cloud-virtu-mai
SSO start URL [None]: https://d-80677ec2cf.awsapps.com/start/
SSO region [None]: eu-west-3
SSO registration scopes [sso:account:access]:
Profile name [AdministratorAccess-115246810561]: cloud-virtu-mai
```

## Connect to OpenStack

- Go to https://iaas.unistra.fr/dashboard/identity/application_credentials/
- Create an application credential with full access
- Download the openrc file, and source it
