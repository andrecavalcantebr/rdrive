# CHECKPOINT — RDrive

Data: 2026-02-28
Status: ativo
Escopo: instalador + GUI Zenity para configuração e operação assistida

## Resumo do estado atual

- GUI criada em `rdrive-gui.sh` para guiar configuração, instalação e autorização.
- Fluxo da GUI simplificado e sem nomenclatura interna de telas exposta ao usuário.
- Configuração carregada de `~/.config/rdrive/rdrive.conf` com opção de reset padrão embutido.
- Edição de variáveis globais e de remotes funcionando em menus dedicados.
- Instalação de scripts via `rdrive-install.sh` integrada à GUI com visualização de log.
- Autorização de remotes via `rdrive-refresh.sh <REMOTE>` integrada à GUI.
- Instalador normaliza paths em runtime, remove `eval` no parser e garante `python3` em `apt`.
- Instalador habilita `user_allow_other` em `/etc/fuse.conf` para suportar `--allow-other`.

## Decisões recentes de arquitetura

- Prioridade para simplicidade e manutenabilidade.
- `MOUNT_BASE`, `CACHE_DIR` e `LOG_DIR` são normalizados para caminhos absolutos no runtime.
- Pasta de montagem do remote tratada como string (`mount_subdir`) sem validação de existência na GUI.
- Caminho de credencial tratado como absoluto e validado (arquivo existente e legível).

## Comportamento atual da GUI

- Menu principal com ações:
  - Visualizar arquivo atual
  - Editar configurações
  - Instalar scripts
  - Instalar remotes
- Visualização de arquivo é somente leitura com botão `Fechar`.
- Em remotes:
  - `NOVO REMOTE` aparece como última opção quando já existem remotes.
  - Se não houver remotes, criação do primeiro é iniciada diretamente.

## Arquivos principais

- `rdrive-gui.sh`
- `rdrive-install.sh`
- `README-pt.md`
- `README-en.md`
- `README.md`

## Pendências recomendadas

- Opcional: reduzir duplicação do parser dentro do `common_block` gerado pelo instalador.
- Opcional: padronizar nomenclatura de funções no instalador (`config_*`, `path_*`, `system_*`) como na GUI.
