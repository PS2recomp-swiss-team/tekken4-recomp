#pragma once
// Optional, read-only access to plates extracted by the player's T5DR launcher. No extraction here.
#include "raylib.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <map>
#include <stdexcept>
#include <utility>
#include <string>
#include <vector>

namespace tekken4_rank_cache
{
    namespace fs = std::filesystem;
    inline fs::path environment(const char *name)
    {
#ifdef _WIN32
        const std::wstring wide(name,name+std::char_traits<char>::length(name));
        const wchar_t *value = _wgetenv(wide.c_str());
#else
        const char *value = std::getenv(name);
#endif
        return value ? fs::path(value) : fs::path();
    }
    // Small bounded JSON reader: decode Unicode/surrogate pairs and respect object scopes.
    // Invalid documents are ignored as a whole; a lookalike key outside roots cannot select an install.
    struct Json
    {
        bool string = false;
        std::string text;
        std::map<std::string, Json> object;
    };
    struct JsonReader
    {
        const std::string &data;
        size_t pos = 0;
        void space() { while(pos<data.size() && (data[pos]==' '||data[pos]=='\t'||data[pos]=='\r'||data[pos]=='\n')) ++pos; }
        bool take(char c) { space(); if(pos<data.size() && data[pos]==c) { ++pos; return true; } return false; }
        bool hex(uint32_t &n)
        {
            n=0;
            for(int i=0;i<4;++i) {
                if(pos>=data.size()) return false;
                const char c=data[pos++];
                if(c>='0'&&c<='9') n=n*16+static_cast<uint32_t>(c-'0');
                else if(c>='a'&&c<='f') n=n*16+static_cast<uint32_t>(c-'a'+10);
                else if(c>='A'&&c<='F') n=n*16+static_cast<uint32_t>(c-'A'+10);
                else return false;
            }
            return true;
        }
        static void utf8(std::string &s,uint32_t n)
        {
            if(n<0x80) s+=static_cast<char>(n);
            else if(n<0x800) { s+=static_cast<char>(0xc0|(n>>6)); s+=static_cast<char>(0x80|(n&63)); }
            else if(n<0x10000) { s+=static_cast<char>(0xe0|(n>>12)); s+=static_cast<char>(0x80|((n>>6)&63)); s+=static_cast<char>(0x80|(n&63)); }
            else { s+=static_cast<char>(0xf0|(n>>18)); s+=static_cast<char>(0x80|((n>>12)&63)); s+=static_cast<char>(0x80|((n>>6)&63)); s+=static_cast<char>(0x80|(n&63)); }
        }
        bool quoted(std::string &s)
        {
            if(!take('"')) return false;
            while(pos<data.size()) {
                const unsigned char c=static_cast<unsigned char>(data[pos++]);
                if(c=='"') return true;
                if(c<0x20) return false;
                if(c!='\\') {
                    if(c<0x80) { s+=static_cast<char>(c); continue; }
                    uint32_t codepoint=0,minimum=0; int continuation=0;
                    if(c>=0xc2&&c<=0xdf) { codepoint=c&31; minimum=0x80; continuation=1; }
                    else if(c>=0xe0&&c<=0xef) { codepoint=c&15; minimum=0x800; continuation=2; }
                    else if(c>=0xf0&&c<=0xf4) { codepoint=c&7; minimum=0x10000; continuation=3; }
                    else return false;
                    while(continuation--) {
                        if(pos>=data.size()) return false;
                        const auto next=static_cast<unsigned char>(data[pos++]);
                        if((next&0xc0)!=0x80) return false;
                        codepoint=(codepoint<<6)|(next&63);
                    }
                    if(codepoint<minimum||codepoint>0x10ffff||(codepoint>=0xd800&&codepoint<=0xdfff)) return false;
                    utf8(s,codepoint); continue;
                }
                if(pos>=data.size()) return false;
                const char escaped=data[pos++];
                switch(escaped) {
                    case '"': case '\\': case '/': s+=escaped; break;
                    case 'b': s+='\b'; break; case 'f': s+='\f'; break;
                    case 'n': s+='\n'; break; case 'r': s+='\r'; break; case 't': s+='\t'; break;
                    case 'u': {
                        uint32_t n=0;
                        if(!hex(n)) return false;
                        if(n>=0xd800&&n<=0xdbff) {
                            if(pos+2>data.size()||data[pos++]!='\\'||data[pos++]!='u') return false;
                            uint32_t low=0;
                            if(!hex(low)||low<0xdc00||low>0xdfff) return false;
                            n=0x10000+((n-0xd800)<<10)+(low-0xdc00);
                        } else if(n>=0xdc00&&n<=0xdfff) return false;
                        // Embedded NUL is never a usable filename; reject rather than truncate it.
                        if(n==0) return false;
                        utf8(s,n); break;
                    }
                    default: return false;
                }
            }
            return false;
        }
        bool value(Json &out,int depth=0)
        {
            if(depth>32) return false;
            space();
            if(pos>=data.size()) return false;
            if(data[pos]=='"') { out.string=true; return quoted(out.text); }
            if(take('{')) {
                if(take('}')) return true;
                do {
                    std::string key;
                    if(!quoted(key)||!take(':')) return false;
                    Json child;
                    if(!value(child,depth+1)||!out.object.emplace(key,std::move(child)).second) return false;
                    if(take('}')) return true;
                } while(take(','));
                return false;
            }
            if(take('[')) {
                if(take(']')) return true;
                do { Json child; if(!value(child,depth+1)) return false; if(take(']')) return true; } while(take(','));
                return false;
            }
            for(const char *literal:{"true","false","null"}) {
                const size_t length=std::char_traits<char>::length(literal);
                if(data.compare(pos,length,literal)==0) { pos+=length; return true; }
            }
            const size_t begin=pos;
            if(data[pos]=='-') ++pos;
            if(pos>=data.size()) return false;
            if(data[pos]=='0') ++pos;
            else { if(data[pos]<'1'||data[pos]>'9') return false; while(pos<data.size()&&data[pos]>='0'&&data[pos]<='9') ++pos; }
            if(pos<data.size()&&data[pos]=='.') {
                const size_t digits=++pos;
                while(pos<data.size()&&data[pos]>='0'&&data[pos]<='9') ++pos;
                if(pos==digits) return false;
            }
            if(pos<data.size()&&(data[pos]=='e'||data[pos]=='E')) {
                ++pos; if(pos<data.size()&&(data[pos]=='+'||data[pos]=='-')) ++pos;
                const size_t digits=pos;
                while(pos<data.size()&&data[pos]>='0'&&data[pos]<='9') ++pos;
                if(pos==digits) return false;
            }
            return pos>begin;
        }
    };
    inline std::string property(const fs::path &file,const char *key,const char *scope=nullptr)
    {
        std::ifstream stream(file,std::ios::binary);
        if(!stream) return {};
        std::string data(65537,'\0'); stream.read(data.data(),static_cast<std::streamsize>(data.size()));
        data.resize(static_cast<size_t>(stream.gcount()));
        if(data.size()>65536) return {};
        JsonReader reader{data};
        Json json;
        if(!reader.value(json)) return {};
        reader.space();
        if(reader.pos!=data.size()) return {};
        const Json *selected=&json;
        if(scope) {
            const auto found=json.object.find(scope);
            if(found==json.object.end()) return {};
            selected=&found->second;
        }
        const auto found=selected->object.find(key);
        return found!=selected->object.end()&&found->second.string ? found->second.text : std::string{};
    }
    inline std::vector<fs::path> folders()
    {
        try {
        // Explicit empty art selection is useful for an original-art-only installation/test.
        const fs::path override=environment("TEKKEN4_T5DR_RANK_CACHE");
        if(!override.empty()) return override==fs::path("off") ? std::vector<fs::path>{} : std::vector<fs::path>{override};
        const fs::path legacy=environment("T5_RANK_ART");
        if(!legacy.empty()) return {legacy};
        fs::path root=environment("OPENRECOMP_T5DR_ROOT");
        fs::path home=environment("OPENRECOMP_HOME");
        if(home.empty()) home=environment("LOCALAPPDATA")/"OpenRecomp";
        if(root.empty()) root=fs::u8path(property(home/"config.json","t5dr","roots"));
        if(root.empty()) return {};
        std::string out=property(root/"launcher.json","out_dir");
        if(out.empty()) out=property(root/"launcher.json","out");
        fs::path output=out.empty() ? fs::path("native") : fs::u8path(out);
        if(output.is_relative()) output=root/output;
        return {output/"cache"/"ranks"};
        } catch(const std::exception &) { return {}; } // invalid UTF-8/path: optional art is unavailable
    }
    struct Plates
    {
        bool tried=false;
        Texture2D texture[37]{};
        void load()
        {
            if(tried) return;
            tried=true;
            for(const auto &folder:folders()) {
                for(int tier=0;tier<37;++tier) {
                    char name[32]; std::snprintf(name,sizeof(name),"rank_%02d.png",tier);
                    const fs::path file=folder/name;
                    std::error_code ec;
                    const auto bytes=fs::file_size(file,ec);
                    if(ec||bytes>1024*1024||bytes<24) continue;
                    // raylib's narrow filename API does not support all Windows paths; read with fs instead.
                    std::ifstream stream(file,std::ios::binary);
                    std::vector<unsigned char> data(static_cast<size_t>(bytes));
                    if(!stream.read(reinterpret_cast<char *>(data.data()),static_cast<std::streamsize>(bytes))) continue;
                    Image img=LoadImageFromMemory(".png",data.data(),static_cast<int>(data.size()));
                    if(img.data && img.width==192 && img.height==96) {
                        texture[tier]=LoadTextureFromImage(img);
                        SetTextureFilter(texture[tier],TEXTURE_FILTER_BILINEAR);
                    }
                    UnloadImage(img);
                }
            }
        }
        bool draw(int tier,Rectangle rect,unsigned char alpha)
        {
            if(tier<0||tier>=37||!alpha) return false;
            load();
            if(!texture[tier].id) return false;
            // Keep the original plate's 2:1 aspect, its baseline and four-pixel name gap.
            rect.x+=rect.width-2*rect.height; rect.width=2*rect.height;
            DrawTexturePro(texture[tier],Rectangle{0,0,192,96},rect,Vector2{0,0},0,
                           Color{255,255,255,static_cast<unsigned char>(std::min(255,alpha*255/128))});
            return true;
        }
    };
}
