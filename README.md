# 🚀 Portable Dev Suite

> **สภาพแวดล้อมการพัฒนาแบบพอร์ทาเบิล ไร้ร่องรอยบนระบบปฏิบัติการหลัก (Zero System Footprint)**
> ระบบจัดการ Environment สำหรับนักพัฒนาที่มาพร้อมระบบจัดการ Python, Git, CUDA และ cuDNN อัตโนมัติ โดยไม่ต้องติดตั้งลงเครื่อง

---

## 📌 ภาพรวมโปรเจกต์ (Overview)

**Portable Dev Suite** ถูกออกแบบมาเพื่อแก้ปัญหาความยุ่งยากในการตั้งค่า Environment บน Windows โดยสร้างระบบนิเวศแบบพอร์ทาเบิลที่แข็งแกร่ง ป้องกันปัญหาขยะตกค้างในระบบ (Global Namespace Pollution), ไม่มีการแก้ไข Registry และหมดปัญหาซอฟต์แวร์ตีกันบนเครื่องหลัก

เหมาะอย่างยิ่งสำหรับการรันโมเดล AI (เช่น TTS, LLMs), โปรเจกต์ Python ที่ซับซ้อน หรือแอปพลิเคชันที่ต้องการใช้ CUDA/cuDNN ขั้นสูง โดยไม่ทำให้ Windows ระบบหลักพัง

## ✨ คุณสมบัติเด่น (Key Features)

- **Zero System Footprint:** ทำงานในโหมดพอร์ทาเบิล 100% ไม่มีการเขียน Registry หรือแก้ไข Environment Variables ของระบบปฏิบัติการหลัก
- **Automated GPU Acceleration:** ระบบสกัดและฉีด PATH สำหรับไฟล์ CUDA และ cuDNN Runtime DLLs อัตโนมัติ
- **Triple-Tier Download Engine:** ระบบดาวน์โหลดสำรองอัตโนมัติ 3 ชั้น (Aria2 $\rightarrow$ cURL $\rightarrow$ PowerShell) เพื่อให้โหลดสำเร็จเสมอ
- **Local CDN Proxy Support:** ระบบตรวจจับ Local TCP Proxy ในวง LAN อัตโนมัติ เพื่อแคชไฟล์ขนาดใหญ่และหลบเลี่ยงการถูกจำกัดความเร็วการดาวน์โหลด
- **Isolated Python & Git:** รัน Python และ Git เฉพาะกิจในโฟลเดอร์ของตัวเอง ป้องกันการตีกับเวอร์ชันที่มีอยู่เดิมในเครื่อง

## 🛠️ ข้อกำหนดทางเทคนิค (Technical Specifications)

- **ระบบปฏิบัติการ:** Windows 10 / Windows 11 (64-bit)
- **เครื่องมือหลัก:** Windows PowerShell 5.1 (ทำงานได้ทันที ไม่ต้องลง PowerShell 7+)
- **สถาปัตยกรรม:** พอร์ทาเบิล 100% (ทำงานผ่านระบบ Relative Path `$PSScriptRoot`)

## 🚀 เริ่มต้นใช้งาน (Quick Start)

1. **โคลนหรือดาวน์โหลด** โปรเจกต์นี้ไปไว้ในโฟลเดอร์ที่คุณต้องการ
2. **ดับเบิลคลิก `start.bat`** เพื่อเริ่มต้นการตั้งค่าและเข้าสู่ Live Shell
3. เมื่ออยู่ใน Live Shell คุณสามารถใช้คำสั่ง `.\setup.ps1` เพื่อจัดการระบบได้ทันที:

```powershell
# ตรวจสอบสเปคเครื่องและไดรเวอร์ฮาร์ดแวร์
.\setup.ps1 -c

# แสดงคู่มือการใช้งานและคำสั่งทั้งหมด
.\setup.ps1 -h

# ติดตั้ง AI Stack แบบครบวงจร (Python, Git, CUDA, cuDNN) แบบอัตโนมัติ
.\setup.ps1 -i all -y

# ระบุติดตั้ง CUDA ตามเวอร์ชันที่ต้องการ
.\setup.ps1 -i cuda -v 12.8
```

## 📦 โครงสร้างโปรเจกต์ (Project Structure)

```text
Portable-Dev-Suite/
├── tools/                # โฟลเดอร์เก็บเครื่องมือที่ดาวน์โหลดมา (Python, Git, CUDA, cuDNN)
├── workspace/            # โฟลเดอร์สำหรับเก็บไฟล์โปรเจกต์และโค้ดของคุณ
├── auto-install.bat      # สคริปต์สำหรับการดาวน์โหลดและติดตั้งแบบคลิกเดียว
├── setup.ps1             # Core Engine ตัวหลักในการจัดการระบบ
└── start.bat             # ไฟล์เริ่มต้นสำหรับเรียกใช้งาน Live Shell
```

## 📄 ลิขสิทธิ์และผู้พัฒนา (License & Author)

- **ผู้พัฒนา (Developer):** [rathanon-dev](https://github.com/rathanon-dev)
- **ลิขสิทธิ์ (License):** MIT License
