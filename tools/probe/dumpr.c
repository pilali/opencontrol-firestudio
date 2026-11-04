#include <stdio.h>
#include <stdlib.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/firewire/IOFireWireLib.h>
#include <libkern/OSByteOrder.h>
// usage: dumpr <addrLo hex> <nquadlets> [stride]  (read only, addrHi=0xffff)
int main(int c,char**v){
  CFMutableDictionaryRef m=IOServiceMatching("IOFireWireDevice"); int vd=0xa92;
  CFDictionarySetValue(m,CFSTR("Vendor_ID"),CFNumberCreate(NULL,kCFNumberIntType,&vd));
  io_service_t s=IOServiceGetMatchingService(kIOMasterPortDefault,m);
  IOCFPlugInInterface**p;SInt32 sc;IOCreatePlugInInterfaceForService(s,kIOFireWireLibTypeID,kIOCFPlugInInterfaceID,&p,&sc);
  IOFireWireLibDeviceRef d;(*p)->QueryInterface(p,CFUUIDGetUUIDBytes(kIOFireWireDeviceInterfaceID),(LPVOID*)&d);(*d)->Open(d);
  UInt32 base=strtoul(v[1],0,16); int n=atoi(v[2]); UInt32 st=c>3?strtoul(v[3],0,16):4; int zeros=0;
  for(int i=0;i<n;i++){UInt32 lo=base+i*st;FWAddress a={0,0xffff,lo};UInt32 q;IOReturn r=(*d)->ReadQuadlet(d,s,&a,&q,false,0);
    if(r){printf("%08x ERR %x\n",lo,r);if(st==4)break;else continue;} q=OSSwapBigToHostInt32(q);
    if(q==0 && st==4){zeros++;continue;} if(zeros){printf("   (%d zero quadlets)\n",zeros);zeros=0;}
    char t[5];for(int k=0;k<4;k++){int ch=(q>>(8*k))&0xff;t[k]=ch>31&&ch<127?ch:'.';}t[4]=0;
    printf("%08x: %08x %s\n",lo,q,t);}
  if(zeros)printf("   (%d zero quadlets)\n",zeros);
  (*d)->Close(d);return 0;}
