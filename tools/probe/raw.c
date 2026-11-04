#include <stdio.h>
#include <stdlib.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/firewire/IOFireWireLib.h>
#include <libkern/OSByteOrder.h>
// raw <addrLo> <maxquads>: prints "index value" until the first error (read only)
int main(int c,char**v){
  CFMutableDictionaryRef m=IOServiceMatching("IOFireWireDevice"); int vd=0xa92;
  CFDictionarySetValue(m,CFSTR("Vendor_ID"),CFNumberCreate(NULL,kCFNumberIntType,&vd));
  io_service_t s=IOServiceGetMatchingService(kIOMasterPortDefault,m);
  IOCFPlugInInterface**p;SInt32 sc;IOCreatePlugInInterfaceForService(s,kIOFireWireLibTypeID,kIOCFPlugInInterfaceID,&p,&sc);
  IOFireWireLibDeviceRef d;(*p)->QueryInterface(p,CFUUIDGetUUIDBytes(kIOFireWireDeviceInterfaceID),(LPVOID*)&d);(*d)->Open(d);
  UInt32 base=strtoul(v[1],0,16); int n=atoi(v[2]);
  for(int i=0;i<n;i++){FWAddress a={0,0xffff,base+4*i};UInt32 q;IOReturn r=(*d)->ReadQuadlet(d,s,&a,&q,false,0);
    if(r){fprintf(stderr,"end at index %d (0x%x) err %x\n",i,4*i,r);break;} printf("%d %08x\n",i,OSSwapBigToHostInt32(q));}
  (*d)->Close(d);return 0;}
