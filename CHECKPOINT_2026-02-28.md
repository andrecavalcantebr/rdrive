# CHECKPOINT — RDrive

Data: 2026-02-28
Status: ativo
Escopo: instalador + GUI Zenity para configuração e operação assistida

## Resumo do estado atual

- GUI criada em `rdrive-gui.sh` para guiar configuração, instalação, autorização e desinstalação.
- Fluxo da GUI simplificado e sem nomenclatura interna de telas exposta ao usuário.
- Configuração carregada de `~/.config/rdrive/rdrive.conf` com opção de reset padrão embutido.
- Edição de variáveis globais e de remotes funcionando em menus dedicados.
- Instalação de scripts via `rdrive-install.sh` integrada à GUI com execução em terminal interativo.
- Autorização de remotes via `rdrive-refresh.sh <REMOTE>` integrada à GUI com execução em terminal interativo.
- Desinstalação completa integrada à GUI com opções de desmontagem prévia e remoção de config.
- Instalador normaliza paths em runtime, remove `eval` no parser e garante `python3` em `apt`.
- Instalador habilita `user_allow_other` em `/etc/fuse.conf` para suportar `--allow-other`.

## Decisões recentes de arquitetura

- Prioridade para simplicidade e manutenabilidade.
- `MOUNT_BASE`, `CACHE_DIR` e `LOG_DIR` são normalizados para caminhos absolutos no runtime.
- Pasta de montagem do remote tratada como string (`mount_subdir`) sem validação de existência na GUI.
- Caminho de credencial tratado como absoluto e validado (arquivo existente e legível).
- Operações longas (instalação, refresh OAuth) executam em terminal interativo visível.

## Comportamento atual da GUI

- Menu principal com ações:
  - Visualizar arquivo atual
  - Editar configurações
  - Instalar scripts
  - Refresh de remote (OAuth) — habilitado apenas após instalação de scripts
  - Desinstalar scripts — habilitado apenas quando scripts estiverem instalados
- Visualização de arquivo é somente leitura com botão `Fechar`.
- Em remotes:
  - `NOVO REMOTE` aparece como última opção quando já existem remotes.
  - Se não houver remotes, criação do primeiro é iniciada diretamente.
- Execução interativa:
  - Instalação e refresh abrem terminal visível com saída em tempo real
  - Log completo salvo em `~/.cache/rdrive-logs/`
  - Pausa ao final para leitura (pressionar Enter para fechar)
- Desinstalação:
  - Remove scripts, links simbólicos e autostart
  - Opcional: desmonta remotes antes de remover
  - Opcional: remove arquivo de configuração

## Arquivos principais

- `rdrive-gui.sh`
- `rdrive-install.sh`
- `README-pt.md`
- `README-en.md`
- `README.md`
- `LICENSE.md`

## Pendências recomendadas

- Opcional: reduzir duplicação do parser dentro do `common_block` gerado pelo instalador.
- Opcional: padronizar nomenclatura de funções no instalador (`config_*`, `path_*`, `system_*`) como na GUI.
