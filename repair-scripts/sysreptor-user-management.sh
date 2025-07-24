#!/bin/bash

# SysReptor User Management Script
# For RTPI-PEN SysReptor Integration

echo "======================================"
echo "🔧 SysReptor User Management"
echo "======================================"

case "${1:-help}" in
    "create-user")
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 create-user <username> <email> [password]"
            echo "If password is not provided, you'll be prompted for it."
            exit 1
        fi
        
        USERNAME="$2"
        EMAIL="$3"
        PASSWORD="${4:-}"
        
        if [ -z "$PASSWORD" ]; then
            echo "Creating superuser: $USERNAME"
            docker compose exec sysreptor-app python3 manage.py createsuperuser --username "$USERNAME" --email "$EMAIL"
        else
            echo "Creating superuser: $USERNAME"
            docker compose exec sysreptor-app python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='$USERNAME').exists():
    User.objects.create_superuser('$USERNAME', '$EMAIL', '$PASSWORD')
    print('✅ Superuser created successfully')
else:
    print('⚠️ User already exists')
"
        fi
        ;;
    
    "list-users")
        echo "Listing SysReptor users:"
        docker compose exec sysreptor-app python3 manage.py shell -c "
from django.contrib.auth import get_user_model
User = get_user_model()
users = User.objects.all()
print(f'Total users: {users.count()}')
print('Users:')
for user in users:
    status = '(superuser)' if user.is_superuser else '(regular)'
    print(f'  - {user.username} <{user.email}> {status}')
"
        ;;
    
    "check-status")
        echo "Checking SysReptor status:"
        docker compose ps sysreptor-app
        echo ""
        echo "Testing connectivity:"
        curl -f http://localhost:9000/health 2>/dev/null && echo "✅ SysReptor is healthy" || echo "❌ SysReptor health check failed"
        ;;
    
    "help"|*)
        echo "Available commands:"
        echo "  create-user <username> <email> [password] - Create a new superuser"
        echo "  list-users                               - List all users"  
        echo "  check-status                             - Check SysReptor status"
        echo "  help                                     - Show this help"
        echo ""
        echo "Examples:"
        echo "  $0 create-user admin admin@example.com"
        echo "  $0 create-user testuser test@example.com MySecurePass123"
        echo "  $0 list-users"
        echo "  $0 check-status"
        ;;
esac
