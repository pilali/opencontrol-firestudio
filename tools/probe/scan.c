// Lecture seule : quelles plages d'adresses répondent ?
#include <stdio.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/firewire/IOFireWireLib.h>
#include <libkern/OSByteOrder.h>
int main(void){
  CFMutableDictionaryRef m=IOServiceMatching("IOFireWireDevice"); int v=0xa92;
  CFDictionarySetValue(m,CFSTR("Vendor_ID"),CFNumberCreate(NULL,kCFNumberIntType,&v));
  io_service_t s=IOServiceGetMatchingService(kIOMasterPortDefault,m);
  IOCFPlugInInterface**p;SInt32 sc;IOCreatePlugInInterfaceForService(s,kIOFireWireLibTypeID,kIOCFPlugInInterfaceID,&p,&sc);
  IOFireWireLibDeviceRef d;(*p)->QueryInterface(p,CFUUIDGetUUIDBytes(kIOFireWireDeviceInterfaceID),(LPVOID*)&d);(*d)->Open(d);
  UInt16 his[]={0xffff,0xfffe,0xfffd,0xffff};
  for(int h=0;h<3;h++) for(UInt32 lo=0x00000000; lo<0xf0000000u+1 && lo>=0 ; lo+=0x00100000){
    if(h==0 && lo<0xc0000000u) {lo=0xc0000000u-0x00100000; continue;}
    if(h>0 && (lo&0x0fffffff)) {continue;}
    FWAddress a={0,his[h],lo};UInt32 q=0;IOReturn r=(*d)->ReadQuadlet(d,s,&a,&q,false,0);
    if(!r) printf("0x%04x%08x = 0x%08x\n",his[h],lo,OSSwapBigToHostInt32(q));
    if(lo>=0xf0000000u) break;
  }
  (*d)->Close(d);return 0;}
