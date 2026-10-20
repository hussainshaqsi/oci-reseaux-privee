\# oci-reseaux-privee



Un serveur \*\*sans IP publique\*\*, injoignable depuis Internet, et accessible uniquement via un tunnel VPN chiffré (WireGuard). Démontre comment isoler une machine du monde extérieur tout en gardant un accès administrateur fiable, avec Terraform (infrastructure) et Ansible (configuration), sur l'offre gratuite d'Oracle Cloud (Always Free).



\## Objectif



La plupart des tutoriels cloud exposent un serveur directement sur Internet avec un port SSH ouvert à tous. Ce projet fait l'inverse : la machine applicative (`private-host`) n'a \*\*aucune IP publique\*\*, au niveau réseau (pas juste un pare-feu qui bloque — Oracle refuse physiquement d'en attribuer une). Le seul point d'entrée du réseau est un \*\*bastion\*\*, lui-même verrouillé pour n'accepter que le trafic WireGuard.



\*\*Preuve finale :\*\* un scan `nmap` depuis Internet ne révèle rien sur le bastion, mais une connexion via le VPN permet un accès SSH complet à la machine privée.



\## Architecture



```mermaid

graph LR

&#x20;   Internet((Internet))

&#x20;   Laptop\["Mon PC<br/>(client WireGuard)"]

&#x20;   IGW\[Internet Gateway]

&#x20;   Bastion\["Bastion<br/>VM.Standard.E2.1.Micro<br/>IP publique + serveur WireGuard"]

&#x20;   NAT\[NAT Gateway]

&#x20;   Private\["private-host<br/>VM.Standard.A1.Flex<br/>AUCUNE IP publique"]



&#x20;   Laptop -. Tunnel chiffré :51820/udp .-> Bastion

&#x20;   Internet --- IGW

&#x20;   IGW --- Bastion

&#x20;   Bastion -- Réseau interne VCN --- Private

&#x20;   Private -. sortie uniquement .-> NAT

&#x20;   NAT --- Internet

```



\- \*\*VCN\*\* (`10.1.0.0/16`) : le réseau privé virtuel qui contient tout.

\- \*\*Sous-réseau public\*\* (`10.1.0.0/24`) : héberge le bastion, seule machine à avoir une IP publique.

\- \*\*Sous-réseau privé\*\* (`10.1.1.0/24`) : héberge `private-host`. L'attribut `prohibit\_public\_ip\_on\_vnic = true` interdit à Oracle d'y attribuer une IP publique, point final — ce n'est pas qu'une règle de pare-feu.

\- \*\*Internet Gateway\*\* : porte à double sens, utilisée uniquement par le bastion.

\- \*\*NAT Gateway\*\* : porte à sens unique (sortie seulement), permet à `private-host` de faire ses mises à jour sans jamais être joignable depuis l'extérieur.

\- \*\*Security Lists\*\* (pare-feu niveau cloud) : le sous-réseau public n'autorise que le port WireGuard (51820/udp). Le sous-réseau privé n'autorise le SSH que depuis le sous-réseau public (le bastion), jamais depuis Internet.



\## Pourquoi deux familles de VM différentes



Le compte Always Free d'Oracle a deux réserves de capacité séparées : 2 VM ARM (`A1.Flex`) et 2 VM AMD (`E2.1.Micro`). Mon premier projet utilise déjà 1 VM ARM, et `private-host` en utilise une seconde (capacité ARM épuisée : 2/2). Le bastion tourne donc sur la réserve AMD, totalement indépendante — ce qui a aussi permis de contourner une pénurie de capacité matérielle Oracle sur `eu-paris-1` (\~40h d'attente avant qu'une VM AMD devienne disponible, un problème connu et documenté de la offre gratuite d'Oracle).



\## Durcissement (Ansible)



Playbook `ansible/hardening.yml`, appliqué aux deux machines :



\- Connexion \*\*uniquement par clé SSH\*\*, mots de passe désactivés

\- Connexion `root` désactivée

\- `fail2ban` : bannissement automatique après plusieurs échecs de connexion

\- `unattended-upgrades` : mises à jour de sécurité automatiques

\- `ufw` activé sur les deux machines — bastion : SSH + WireGuard uniquement ; `private-host` : SSH uniquement depuis le sous-réseau du bastion



\## Déploiement



```bash

\# 1. Infrastructure (réseau + VMs)

terraform init

terraform plan

terraform apply



\# 2. VPN WireGuard sur le bastion

cd ansible

ansible-playbook -i inventory.ini wireguard-server.yml



\# 3. Durcissement des deux machines

ansible-playbook -i inventory.ini hardening.yml



\# 4. Une fois le VPN vérifié fonctionnel, fermeture définitive du SSH public

\# (suppression de la règle temporaire dans network.tf, puis :)

terraform apply

```



Client WireGuard (ex. sur son propre PC) : importer une configuration pointant vers `<ip\_publique\_bastion>:51820`, avec `AllowedIPs = 10.1.0.0/16`.



\## Preuve



\*\*1. Scan depuis Internet — le bastion ne répond à rien :\*\*



!\[Scan nmap montrant tous les ports filtrés]<img width="932" height="192" alt="image" src="https://github.com/user-attachments/assets/84705eb2-cb50-4ba4-9fe5-7a96fd3e700c" />




\*\*2. Accès SSH à `private-host` fonctionnel, uniquement via le VPN :\*\*



!\[Connexion SSH réussie via le tunnel WireGuard]<img width="958" height="910" alt="image" src="https://github.com/user-attachments/assets/68a4d771-8500-49be-a3ff-7b2e59ac2ee8" />




\## Pièges rencontrés



\- \*\*Pénurie de capacité Oracle\*\* : la création de VM AMD a échoué pendant \~40h ("Out of host capacity"), un problème matériel côté Oracle, pas une erreur de configuration — résolu en recommençant automatiquement (`retry.ps1`) jusqu'à ce qu'un slot se libère.

\- \*\*Double pare-feu caché\*\* : au-delà des Security Lists (niveau cloud), les images Ubuntu d'Oracle embarquent leur propre pare-feu `iptables`, déjà configuré pour tout rejeter sauf SSH/ICMP. Deux bugs en ont découlé : le port WireGuard bloqué en entrée (`INPUT`), puis le trafic VPN bloqué en transit vers `private-host` (`FORWARD`) — les deux causés par des règles ajoutées \*après\* la règle de rejet existante au lieu d'avant (`iptables` s'arrête à la première règle qui correspond).

\- \*\*Dérive d'état Terraform\*\* : une règle de pare-feu avait disparu du fichier `.tf` sans explication ; `terraform plan` ne la voyait plus comme manquante puisque le fichier ne la demandait plus — réglé en la réécrivant et en ré-appliquant.



\## Nettoyage



```bash

terraform destroy

```

