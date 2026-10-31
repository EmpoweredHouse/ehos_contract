# Enable the eh-os-contract plugin

This page tells how to enable the Claude Code plugin `eh-os-contract` in an application. It is for a
developer whose application uses the engine `eh_os_contract`. The plugin gives an assistant skills
that write contracts by the rules of the engine.

## What the skills do

| Skill | Use it |
| --- | --- |
| `module-boundary-check` | before you add an entity, an action, a screen or a table: does it go through a contract? |
| `contract-distillation` | to turn the notes of a workshop into a domain and contracts |
| `add-event` | to declare a new event |
| `change-contract` | before you change a contract that has events in the log |
| `write-decider` | to write the code that decides the commands of a unit |
| `write-reaction` | to declare and write a reaction or a read model |

## Before you start

- Claude Code.
- Read access to the GitHub repository `EmpoweredHouse/eh-os-contract`. The repository is private.

## Steps

1. Find the latest release of the plugin: a tag `eh-os-contract-plugin-vX.Y.Z` of the repository.
2. Add the marketplace and the plugin to `.claude/settings.json` of your application, at that tag:

   ```json
   {
     "extraKnownMarketplaces": {
       "eh-os-contract": {
         "source": {
           "source": "github",
           "repo": "EmpoweredHouse/eh-os-contract",
           "ref": "eh-os-contract-plugin-vX.Y.Z"
         }
       }
     },
     "enabledPlugins": {
       "eh-os-contract@eh-os-contract": true
     }
   }
   ```

3. If your machine has no SSH key for GitHub, set `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1`. Then give git
   a credential for GitHub. `gh auth setup-git` does this for each HTTPS git command on the machine,
   with the token of `gh`.
4. Start Claude Code in the application, or run `/reload-plugins`.

**Result:** the skills show in Claude Code, for example `/eh-os-contract:change-contract`.

The template of `ehos_app` writes these settings into each project that it generates. To take a new
version of the plugin, change the tag in `ref`.

## Next steps

- [Getting started](../../packages/eh_os_contract/docs/getting-started.md): install the engine.
- [Write a domain, a contract and a process module](../../packages/eh_os_contract/docs/contract.md).
