# Meshlets (in zig and DirectX 12)

This is a project that I use to learn more about both Zig and DX12 graphics API. I'm exploring the use of mesh shaders and meshlets as a primitive. 

![](content/cover.png)

## 🎯 Learning Goals
- [x] Understanding and creating a mesh shader pipeline
- [x] Parsing a model and generating meshlets through `zmesh`
- [x] Rendering a model through a mesh shader pipeline
- [ ] Measuring the performance difference between the normal vertex pipe and mesh shaders
- [ ] Implementing gpu-accelerated occlusion culling on meshlets

## 🛠️ How to Run
### **1. Install Zig**
Make sure you have Zig installed. You can download it from:  
🔗 [Ziglang.org](https://ziglang.org/download/)  

Or install via package manager:
```sh
# Linux (Debian-based)
sudo apt install zig

# macOS (Homebrew)
brew install zig

# Windows (Scoop)
scoop install zig

# Windows (choco)
choco install zig
```

### **2. Clone the repository**
```sh
git clone https://github.com/yourusername/your-zig-project.git
cd your-zig-project
```

### **3. Build the project**
```sh
zig build
```

### **4. Build the project**
```sh
./zig-out/bin/zig-dx12.exe
```