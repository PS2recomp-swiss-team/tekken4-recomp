// Synthetic renderer/files only. No game, game art, guest RAM or network.
#include "../runtime/tekken4_badge_draw.h"
#include "../runtime/tekken4_rank_cache.h"
#include <cassert>
#include <iostream>

namespace fs=std::filesystem;
static bool close(float a,float b) { return std::abs(a-b)<0.002f; }
static void write(const fs::path &path,const std::string &data) {
    fs::create_directories(path.parent_path());
    std::ofstream(path,std::ios::binary).write(data.data(),static_cast<std::streamsize>(data.size()));
}
static void env(const wchar_t *name,const fs::path &value={}) { assert(_wputenv_s(name,value.c_str())==0); }
static std::string jsonPath(const fs::path &path) {
    std::string text=path.generic_u8string(),out;
    for(char c:text) { if(c=='"'||c=='\\') out+='\\';out+=c; }
    return out;
}
int main() {
    using namespace tekken4_badge_draw;
    for(const Rectangle viewport:{Rectangle{0,0,640,448},Rectangle{0,0,1280,896},
            Rectangle{0,0,1920,1080},Rectangle{188.57f,0,1542.86f,1080},Rectangle{0,0,1280,720}}) {
        for(int nameX:{40,480}) {
            const int nameY=47;
            const Rectangle r=bounds(viewport.x,viewport.y,viewport.width,viewport.height,nameX,nameY);
            assert(close(r.height,14*viewport.height/448));
            assert(close(r.width/r.height,1.6f));
            assert(close(r.y+r.height,viewport.y+65*viewport.height/448));
            assert(close(viewport.x+nameX*viewport.width/640-(r.x+r.width),4*viewport.width/640));
            for(int tier=0;tier<37;++tier) {
                test_renderer::reset(); draw(tier,r,1);
                assert(!test_renderer::vertices.empty());
                for(Vector2 vertex:test_renderer::vertices) {
                    assert(vertex.x>=r.x-0.002f&&vertex.x<=r.x+r.width+0.002f);
                    assert(vertex.y>=r.y-0.002f&&vertex.y<=r.y+r.height+0.002f);
                }
                for(Color color:test_renderer::colors) assert(color.a==255);
            }
            test_renderer::reset();draw(-1,r,1);draw(37,r,1);
            assert(test_renderer::vertices.empty()); // guests/unknown tiers never draw
            draw(19,r,0);
            for(Color color:test_renderer::colors) assert(color.a==0);
            test_renderer::reset();draw(19,r,0.5f);
            for(Color color:test_renderer::colors) assert(color.a==127);
        }
    }
    const fs::path fixture=fs::current_path()/"fixtures";
    fs::create_directories(fixture);
    env(L"TEKKEN4_T5DR_RANK_CACHE");env(L"T5_RANK_ART");env(L"OPENRECOMP_T5DR_ROOT");
    env(L"OPENRECOMP_HOME",fixture/"home");env(L"LOCALAPPDATA",fixture/"local");
    using namespace tekken4_rank_cache;
    assert(folders().empty());
    env(L"T5_RANK_ART",fixture/"legacy");assert(folders()==std::vector<fs::path>{fixture/"legacy"});
    env(L"TEKKEN4_T5DR_RANK_CACHE",L"off");assert(folders().empty());
    env(L"TEKKEN4_T5DR_RANK_CACHE",fixture/"explicit");assert(folders()==std::vector<fs::path>{fixture/"explicit"});
    env(L"TEKKEN4_T5DR_RANK_CACHE");env(L"T5_RANK_ART");
    const fs::path root=fixture/fs::u8path("T5-\xc3\xa4\xf0\x9f\x8e\xae");
    const std::string escaped=jsonPath(fixture)+"/T5-\\u00e4\\ud83c\\udfae";
    write(fixture/"home/config.json","{\"other\":{\"t5dr\":\"wrong\"},\"roots\":{\"t5dr\":\""+escaped+"\"}}");
    assert(folders()==std::vector<fs::path>{root/"native/cache/ranks"});
    write(root/"launcher.json",R"({"ignored":{"out":"wrong"},"out":"custom-output"})");
    assert(folders()==std::vector<fs::path>{root/"custom-output/cache/ranks"});
    write(root/"launcher.json",R"({"out_dir":"custom-\u00e4","out":"ignored"})");
    assert(folders()==std::vector<fs::path>{root/fs::u8path("custom-\xc3\xa4")/"cache/ranks"});
    write(root/"launcher.json",R"({"out":false})");assert(folders()==std::vector<fs::path>{root/"native/cache/ranks"});
    for(const std::string invalid:{"{\"roots\":{\"t5dr\":\"x\"},}","{\"roots\":{\"t5dr\":\"x\"}}garbage",
        "{\"roots\":{\"t5dr\":\"\\ud800\"}}","{\"roots\":{\"t5dr\":\"\\udc00\"}}",
        "{\"roots\":{\"t5dr\":\"\\uZZZZ\"}}","{\"roots\":{\"t5dr\":\"\\u0000\"}}",
        "{\"t5dr\":\"outside-roots\"}","{\"roots\":{\"t5dr\":\"a\",\"t5dr\":\"b\"}}"}) {
        write(fixture/"home/config.json",invalid);assert(folders().empty());
    }
    write(fixture/"home/config.json",std::string("{\"roots\":{\"t5dr\":\"")+"\xc0\xaf"+"\"}}");assert(folders().empty());
    write(fixture/"home/config.json",std::string(65537,' '));assert(folders().empty());
    env(L"OPENRECOMP_T5DR_ROOT",root);assert(folders()==std::vector<fs::path>{root/"native/cache/ranks"});
    env(L"OPENRECOMP_T5DR_ROOT");env(L"OPENRECOMP_HOME");
    write(fixture/"local/OpenRecomp/config.json","{\"roots\":{\"t5dr\":\""+jsonPath(root)+"\"}}");
    assert(folders()==std::vector<fs::path>{root/"native/cache/ranks"});
    // Stub image decoding validates the caller's dimension/size/cache fallback contract.
    env(L"TEKKEN4_T5DR_RANK_CACHE",fixture/"missing-plates");
    Plates absent;test_renderer::reset();assert(!absent.draw(19,{0,0,16,10},128));
    assert(test_renderer::textureDraws==0);
    env(L"TEKKEN4_T5DR_RANK_CACHE",fixture/"plates");
    std::string synthetic(24,'\0');synthetic[0]=1;write(fixture/"plates/rank_19.png",synthetic);
    write(fixture/"plates/rank_22.png",std::string(24,'\0')); // decoder rejects malformed image
    write(fixture/"plates/rank_20.png",std::string(1024*1024+1,'\0')); // rejected before decoder
    Plates plates;const int before=test_renderer::imageLoads;
    assert(!plates.draw(-1,{0,0,16,10},128));assert(!plates.draw(37,{0,0,16,10},128));
    assert(!plates.draw(19,{0,0,16,10},0));assert(test_renderer::imageLoads==before);
    assert(plates.draw(19,{10,20,16,10},64));assert(test_renderer::tint.a==127);
    assert(close(test_renderer::target.x,6)&&close(test_renderer::target.width,20));
    assert(close(test_renderer::target.y+test_renderer::target.height,30));
    assert(!plates.draw(22,{0,0,16,10},128));
    const int loaded=test_renderer::imageLoads;
    assert(plates.draw(19,{0,0,16,10},128));assert(test_renderer::imageLoads==loaded);
    assert(test_renderer::tint.a==255);
    std::cout<<"rank badges: geometry, 37 tiers, guests, fade, scoped Unicode cache discovery, fallback all passed\n";
}
