import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { loadingCard, reminderCard } from '../model/CardData';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params = want.parameters;
    const formId = params === undefined ? '' : params['ohos.extra.param.key.form_identity'] as string;
    this.refresh(formId);
    return formBindingData.createFormBindingData(loadingCard());
  }

  onFormEvent(formId: string, message: string): void {
    this.refresh(formId);
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  onRemoveForm(formId: string): void {}

  private async refresh(formId: string): Promise<void> {
    if (formId.length === 0) return;
    try {
      const data = await reminderCard(this.context);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (e) {
      hilog.warn(0x0000, 'nuanlin', 'form update failed: %{public}s', JSON.stringify(e));
    }
  }
}
