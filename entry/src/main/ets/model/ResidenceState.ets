import { Person, ResidenceInput } from './Api';

export function residenceInput(person: Person, id: string): ResidenceInput {
  if (!person || person.id !== id || !Number.isInteger(person.revision) || (person.revision ?? 0) < 1) {
    throw new Error('无法核对档案及版本，请重新读取。');
  }
  const input: ResidenceInput = { address: person.address ?? '', phone: person.phone ?? '',
    living: person.living ?? '', contactName: person.contactName ?? '', contactPhone: person.contactPhone ?? '' };
  if ([input.address, input.phone, input.living, input.contactName, input.contactPhone].some(value => value.includes('*'))) {
    throw new Error('当前账号只能查看脱敏资料，不能在此修改。');
  }
  return input;
}

export function validateResidence(input: ResidenceInput): string {
  if (!input.address.trim()) return '请补充当前居住地址，核实后再保存。';
  if (input.address.length > 500) return '居住地址最多500字。';
  if (input.living.length > 200) return '居住情况最多200字。';
  if (input.contactName.length > 60) return '联系人姓名最多60字。';
  if ([input.address, input.phone, input.living, input.contactName, input.contactPhone].some(value => value.includes('*'))) {
    return '请填写核实后的实际资料，不能保存脱敏占位内容。';
  }
  if ([input.phone, input.contactPhone].some(value => value.length > 0 && !/^[+\d\s()-]{7,24}$/.test(value))) {
    return '联系电话请输入完整手机号或固定电话，未知可留空。';
  }
  return '';
}
