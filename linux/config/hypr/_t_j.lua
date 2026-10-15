hl.plugin.load(os.getenv("HOME").."/.local/share/hypr3d-src/build/hypr3d.so")
hl.plugin.hypr3d.config({ world={panorama=os.getenv("HOME").."/.local/share/hypr3d-world/panorama/city_rooftop.jpg",grid=false},windows={focus_on_aim=false},player={flying=true,spawn={x=0,y=2,z=12}},map={path=os.getenv("HOME").."/.local/share/hypr3d-world/map/map.glb",flat=true,collision=true,emissive_scale=1.0,transform={position={x=0,y=0,z=0},rotation={x=0,y=0,z=0},scale={x=1,y=1,z=1}}} })
hl.bind("SUPER + F12", hl.plugin.hypr3d.toggle)
