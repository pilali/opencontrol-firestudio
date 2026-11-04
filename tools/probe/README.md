# Outils de sonde

Petits outils en C pour explorer la zone mixeur de la FireStudio (`0xFFFFE0700000`).
Fermez l'application FireStudio Mixer avant de les utiliser : l'accès FireWire est exclusif.

```sh
make            # construit build/raw, build/dumpr, build/scan, build/wq
build/scan                    # plages d'adresses qui répondent (lecture seule)
build/raw e0700000 1290       # vide la zone mixeur : « index valeur » (lecture seule)
build/dumpr e0700000 64       # affichage compact avec ASCII (lecture seule)
build/wq 10ac 24              # ÉCRIT un quadlet (décalage dans la zone, valeur) puis relit
```

`wq` refuse tout décalage hors des paramètres (`0x0038`–`0x1164`) : en-tête, noms et vu-mètres sont protégés. N'écrivez que des paramètres documentés dans
[../../docs/register-map.md](../../docs/register-map.md).
