// wq <hex offset in the mixer area> <hex value>: writes one quadlet at 0xFFFFE0700000+offset, then reads it back
#include <stdio.h>
#include <stdlib.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/firewire/IOFireWireLib.h>
#include <libkern/OSByteOrder.h>
int main(int c,char**v){
  if(c<3)return 2; UInt32 off=strtoul(v[1],0,16), val=strtoul(v[2],0,16); if(off<0x38||off>=0x1168||off&3){fprintf(stderr,"offset refused: only parameters 0x0038-0x1164 are writable\n");return 2;}
  CFMutableDictionaryRef m=IOServiceMatching("IOFireWireDevice"); int vd=0xa92;
  CFDictionarySetValue(m,CFSTR("Vendor_ID"),CFNumberCreate(NULL,kCFNumberIntType,&vd));
  io_service_t s=IOServiceGetMatchingService(kIOMasterPortDefault,m);
  IOCFPlugInInterface**p;SInt32 sc;IOCreatePlugInInterfaceForService(s,kIOFireWireLibTypeID,kIOCFPlugInInterfaceID,&p,&sc);
  IOFireWireLibDeviceRef d;(*p)->QueryInterface(p,CFUUIDGetUUIDBytes(kIOFireWireDeviceInterfaceID),(LPVOID*)&d);(*d)->Open(d);
  FWAddress a={0,0xffff,0xe0700000+off}; UInt32 q;
  (*d)->ReadQuadlet(d,s,&a,&q,false,0); printf("before: 0x%08x\n",OSSwapBigToHostInt32(q));
  IOReturn r=(*d)->WriteQuadlet(d,s,&a,OSSwapHostToBigInt32(val),false,0); printf("write 0x%08x -> 0x%x\n",val,r);
  (*d)->ReadQuadlet(d,s,&a,&q,false,0); printf("after: 0x%08x\n",OSSwapBigToHostInt32(q));
  (*d)->Close(d);return r?1:0;}
