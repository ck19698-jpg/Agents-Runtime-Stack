# Agents-Runtime-Stack

ติดตั้งทีม Agent บน Ubuntu ด้วย Docker โดยใช้โครงต่อหนึ่งทีมดังนี้:

- OpenClaw = runtime หลักของทีม
- Pi Operator = Runtime Engineer ประจำทีม
- Hermes Agent = runtime ทดลอง เปิดด้วย Docker profile

## เป้าหมาย

Fresh Ubuntu → หนึ่งคำสั่ง → เปิด setup wizard → ได้ทีม runtime ที่แยก state, ports, network และ business context ออกจากทีมอื่น

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/ck19698-jpg/Agents-Runtime-Stack/main/install.sh | bash
```

## โครงข้อมูล

```text
$HOME/Agents-Runtime-Stack/        # โค้ดและสคริปต์จาก GitHub
$HOME/teams/<team-slug>/           # state จริงของแต่ละทีม
├── .openclaw/
├── .openclaw-auth-profile-secrets/
├── .pi/
├── .hermes/
├── shared/
├── logs/
└── backups/
```

Runtime state และ secrets ไม่ถูกเก็บใน Git

## หลักสำคัญ

- 1 ทีม = 1 Docker Compose project
- 1 ทีม = 1 OpenClaw + 1 Pi Operator
- Hermes เป็น optional experimental profile
- Business Alias เปลี่ยนได้ แต่ Canonical Agent codenames คงเดิม
- ห้ามประกาศว่า ready จน health, control, model, identity, channels และ permissions ผ่านจริง
