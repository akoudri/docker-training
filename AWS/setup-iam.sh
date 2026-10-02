#!/usr/bin/env bash
# Crée (ou supprime) l'utilisateur IAM de formation et ses droits.
# À exécuter UNE FOIS avec un profil administrateur du compte (ex : aws login --profile admin).
# Crée aussi le VPC par défaut de la région s'il n'existe pas.
#
# Usage :
#   ./setup-iam.sh create <utilisateur>   crée l'utilisateur, son mot de passe console et ses droits
#   ./setup-iam.sh delete <utilisateur>   supprime l'utilisateur et la politique associée
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_NAME="docker-training-policy"

# Politiques gérées par AWS attachées en plus de la politique du TP
MANAGED_POLICIES=(
  arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess   # autorise "aws login"
  arn:aws:iam::aws:policy/IAMUserChangePassword          # changement du mot de passe initial
)

ACTION="${1:-}"
USER_NAME="${2:-}"
[ -n "$ACTION" ] && [ -n "$USER_NAME" ] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::$ACCOUNT:policy/$POLICY_NAME"
REGION="${AWS_REGION:-$(aws configure get region || true)}"
REGION="${REGION:-eu-west-3}"

create() {
  if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
    aws iam create-policy --policy-name "$POLICY_NAME" \
      --policy-document "file://$SCRIPT_DIR/iam-policy.json" >/dev/null
    echo "Politique créée : $POLICY_NAME"
  fi

  # Fargate (ecs.sh comme Terraform) s'appuie sur le VPC par défaut de la région
  if [ "$(aws ec2 describe-vpcs --region "$REGION" --filters Name=is-default,Values=true \
          --query 'Vpcs[0].VpcId' --output text)" = "None" ]; then
    aws ec2 create-default-vpc --region "$REGION" >/dev/null
    echo "VPC par défaut créé dans $REGION"
  fi

  aws iam create-user --user-name "$USER_NAME" >/dev/null
  echo "Utilisateur créé : $USER_NAME"

  for arn in "$POLICY_ARN" "${MANAGED_POLICIES[@]}"; do
    aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$arn"
  done

  local password
  password="$(openssl rand -base64 18)Aa1!"
  aws iam create-login-profile --user-name "$USER_NAME" \
    --password "$password" --password-reset-required >/dev/null

  cat <<EOF

Connexion console : https://$ACCOUNT.signin.aws.amazon.com/console
Utilisateur       : $USER_NAME
Mot de passe      : $password   (à changer à la première connexion)

Puis, sur le poste du stagiaire :
  aws login --profile training --region eu-west-3
  export AWS_PROFILE=training
EOF
}

delete() {
  local arn key
  for arn in $(aws iam list-attached-user-policies --user-name "$USER_NAME" \
                 --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-user-policy --user-name "$USER_NAME" --policy-arn "$arn"
  done
  for key in $(aws iam list-access-keys --user-name "$USER_NAME" \
                 --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
    aws iam delete-access-key --user-name "$USER_NAME" --access-key-id "$key"
  done
  if aws iam get-login-profile --user-name "$USER_NAME" >/dev/null 2>&1; then
    aws iam delete-login-profile --user-name "$USER_NAME"
  fi
  aws iam delete-user --user-name "$USER_NAME"
  echo "Utilisateur supprimé : $USER_NAME"

  # La politique n'est supprimée que si plus aucun utilisateur ne l'utilise
  if [ "$(aws iam get-policy --policy-arn "$POLICY_ARN" \
          --query 'Policy.AttachmentCount' --output text 2>/dev/null || echo -1)" = "0" ]; then
    aws iam delete-policy --policy-arn "$POLICY_ARN"
    echo "Politique supprimée : $POLICY_NAME"
  fi
}

case "$ACTION" in
  create) create ;;
  delete) delete ;;
  *)      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
