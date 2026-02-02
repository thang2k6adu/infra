đọc kĩ file service

từ name hãy tạo: tên folder, namespace, fullName override, configmap name, secret name, còn gì nữa thì hãy suggest thêm, ko còn thì thôi

image thì đương nhiên là mapping tthẳng, ko vấn đề gì
imagepullsecret thì cũng mapping tthẳng, ko vấn đề gì

trong network, port sẽ mapping với service port và target port, đồng thời mapping với 
healthcheck:
  liveness:
    path: /api/health

  readiness:
    path: /api/health

  startup:
    path: /api/health

domain thì mapping với domain

resource thì đương nhiên map

autoscaling thì tự scale

health check cũng tự map

storage và persistence thì cũng ko vấn đề gì

bắt đầu sửa

linux

chmod +x gen-values.sh
./gen-values.sh

window
cài 
Install-Module powershell-yaml -Scope CurrentUser

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\gen-values.ps1

window

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\gen-folder.ps1

window

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\scripts\create-service.ps1

window

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\seal-env.ps1

