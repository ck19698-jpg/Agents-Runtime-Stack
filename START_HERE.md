# START HERE

## ติดตั้งจาก Fresh Ubuntu หรือเครื่องที่มี Docker อยู่แล้ว

รันในบัญชีผู้ใช้ปกติ ห้ามรันเป็น root:

```bash
curl -fsSL https://raw.githubusercontent.com/ck19698-jpg/Agents-Runtime-Stack/main/install.sh | bash
```

Installer จะ:

1. ตรวจ Ubuntu
2. ติดตั้ง Git, curl, OpenSSL และ Docker/Compose หากยังไม่มี
3. Clone repo ไปที่ `$HOME/Agents-Runtime-Stack`
4. สร้างทีมที่ `$HOME/teams/<team-slug>`
5. สร้าง Gateway token และ keyring password โดยไม่แสดงค่าออกหน้าจอ
6. เปิด OpenClaw onboarding
7. เริ่ม Gateway และตรวจ `/healthz` กับ `/readyz`

## คำสั่งประจำทีม

ตัวอย่างทีม `lastcore-agency`:

```bash
$HOME/teams/lastcore-agency/stack status
$HOME/teams/lastcore-agency/stack logs
$HOME/teams/lastcore-agency/stack restart
$HOME/teams/lastcore-agency/stack ready
$HOME/teams/lastcore-agency/stack pi
```

## ขอบเขต V1

พร้อมในรอบแรก:

- OpenClaw Gateway แบบแยกต่อทีม
- OpenClaw CLI
- Pi Operator แบบ container แยกและมี state ของทีม
- Team state, shared workspace, logs และ backups แยกจาก repo

ยังไม่เปิดใน V1:

- Hermes experimental profile
- Docker socket สำหรับ Pi
- Channel bindings
- Six-Squad persona/business wizard

สิ่งเหล่านี้จะเปิดทีละ Gate หลัง Runtime หลักผ่านจริง เพื่อไม่ให้คำว่า “พร้อม” หมายถึงเพียง container ยังไม่ตาย
