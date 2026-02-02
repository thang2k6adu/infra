1. Hardcoded Directory Structure 🔧
bash
# Vấn đề: Cấu trúc thư mục cứng nhắc
servicesPath="$rootDir/services"  # Luôn là "services"
tenantDir="$clusterPath/tenants/$serviceName"  # Luôn là "tenants"

# Hậu quả:
# - Không thể thay đổi cấu trúc project
# - Không thể support multiple service directories
# - Không thể có naming pattern khác nhau
2. Fixed File Naming Convention 📁
bash
# Vấn đề: Tên file cố định không thể cấu hình
files=("namespace.yaml" "kustomization.yaml" "values.yaml" "configmap.yaml" "sealed-secret.yaml")

# Hậu quả:
# - Mọi service phải dùng cùng tên file
# - Không thể thêm/ bớt file types mà không sửa code
# - Không thể có custom file structure
3. Rigid Workflow Steps 🔄
bash
# Vấn đề: Workflow 3 bước cố định
1. gen-folder.sh
2. gen-values.sh  
3. seal-env.sh

# Hậu quả:
# - Không thể thêm pre/post processing steps
# - Không thể reorder steps
# - Không thể skip steps tùy từng cluster
# - Không thể conditional execution